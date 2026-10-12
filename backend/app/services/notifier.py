"""Decides *who* gets pinged about *what*, then hands off to FCM.

Two triggers, each sent at most once per user (NotificationLog):
  deadline_72h  a job in the user's eligible feed closes in < URGENT_DEADLINE_HOURS
                (the feed already excludes jobs the user marked Applied)
  admit_card    a new admit-card alert that matches an exam the user applied to

ADHD-friendly restraint: quiet hours (default 22:00–07:00 local) hold back pings
unless a deadline is under QUIET_HOURS_OVERRIDE_HOURS. Held pings go out on the
first run after quiet hours, because nothing is logged until delivery succeeds.
"""

from __future__ import annotations

import logging
import re
import uuid
from collections import defaultdict
from collections.abc import Awaitable
from datetime import UTC, datetime, timedelta
from typing import Protocol
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.domain.enums import ApplicationStatus, ItemKind, ItemStatus
from app.models import (
    DeviceToken,
    DiscoveredItem,
    JobPost,
    NotificationLog,
    PostDetail,
    User,
    UserApplication,
)
from app.services.fcm_service import SendResult
from app.services.feed import build_feed

log = logging.getLogger(__name__)


class Sender(Protocol):
    def __call__(
        self, target: str, title: str, body: str, data: dict[str, str], *, target_kind: str = "token"
    ) -> Awaitable[SendResult]: ...


# =============================================================================
# Pure helpers
# =============================================================================


def in_quiet_hours(now: datetime, settings: Settings) -> bool:
    hour = now.astimezone(ZoneInfo(settings.timezone)).hour
    start, end = settings.quiet_hours_start, settings.quiet_hours_end
    if start == end:
        return False
    return (hour >= start or hour < end) if start > end else (start <= hour < end)


_STOPWORDS = {
    "the",
    "of",
    "and",
    "for",
    "in",
    "to",
    "a",
    "an",
    "&",
    "admit",
    "card",
    "cards",
    "call",
    "letter",
    "hall",
    "ticket",
    "exam",
    "examination",
    "recruitment",
    "online",
    "form",
    "notification",
    "post",
    "posts",
    "various",
    "out",
    "released",
    "download",
    "phase",
    "tier",
    "stage",
    "limited",
    "ltd",
    "india",
    "indian",
    "government",
    "govt",
    "advt",
    "no",
}
_YEAR = re.compile(r"^(19|20)\d\d$")


def _tokens(text: str) -> set[str]:
    return {
        w
        for w in re.findall(r"[a-z0-9]+", text.lower())
        if len(w) > 1 and w not in _STOPWORDS and not _YEAR.match(w)
    }


def _acronyms(organization: str) -> set[str]:
    """Both 'rrb' (all words) and 'rb' (without stopwords) for 'Railway Recruitment Board'."""
    words = re.findall(r"[A-Za-z]+", organization)
    full = "".join(w[0] for w in words).lower()
    short = "".join(w[0] for w in words if w.lower() not in _STOPWORDS).lower()
    return {a for a in (full, short) if len(a) > 1}


def alert_matches_job(alert_title: str, exam_name: str, organization: str | None) -> bool:
    """True when the alert names this exam, not just the same organisation.

    Needs >= 2 shared tokens, at least one of them specific to the exam name, so
    "SSC CHSL Admit Card" doesn't match an SSC CGL application and
    "RRB Section Controller Admit Card" doesn't match RRB NTPC.
    """
    alert = _tokens(alert_title)
    org_tokens = _tokens(organization or "") | _acronyms(organization or "")
    exam_specific = _tokens(exam_name) - org_tokens
    shared = alert & (exam_specific | org_tokens)
    return len(shared) >= 2 and bool(alert & exam_specific)


# =============================================================================
# Delivery
# =============================================================================


async def _devices_by_user(session: AsyncSession) -> dict[uuid.UUID, list[DeviceToken]]:
    out: dict[uuid.UUID, list[DeviceToken]] = defaultdict(list)
    for token in await session.scalars(select(DeviceToken)):
        out[token.user_id].append(token)
    return out


async def _already_sent(session: AsyncSession, user_id: uuid.UUID, kind: str, ref: str) -> bool:
    return (
        await session.scalar(
            select(NotificationLog.id).where(
                NotificationLog.user_id == user_id, NotificationLog.kind == kind, NotificationLog.ref == ref
            )
        )
    ) is not None


async def _deliver(
    session: AsyncSession,
    *,
    user_id: uuid.UUID,
    tokens: list[DeviceToken],
    kind: str,
    ref: str,
    title: str,
    body: str,
    data: dict[str, str],
    sender: Sender,
    now: datetime,
) -> bool:
    delivered = False
    for device in list(tokens):
        result = await sender(device.token, title, body, data, target_kind=device.kind)
        if result.ok:
            device.last_success_at, device.failures = now, 0
            delivered = True
        elif result.invalid_token:
            tokens.remove(device)
            await session.delete(device)
        else:
            device.failures += 1
    if delivered:
        session.add(NotificationLog(user_id=user_id, kind=kind, ref=ref, sent_at=now))
    await session.commit()
    return delivered


# =============================================================================
# Triggers
# =============================================================================


async def notify_urgent_deadlines(
    session: AsyncSession, sender: Sender, *, now: datetime | None = None, settings: Settings | None = None
) -> int:
    settings = settings or get_settings()
    now = now or datetime.now(UTC)
    quiet = in_quiet_hours(now, settings)
    devices = await _devices_by_user(session)
    if not devices:
        return 0
    users = await session.scalars(select(User).where(User.id.in_(list(devices)), User.is_active))
    sent = 0
    for user in users:
        if user.profile is None:
            continue
        feed = await build_feed(session, user.profile, now=now)
        for item in [i for i in [feed.hero, *feed.up_next] if i is not None]:
            if item.hours_remaining >= settings.urgent_deadline_hours:
                continue
            if quiet and item.hours_remaining >= settings.quiet_hours_override_hours:
                continue
            ref = str(item.job_post_id)
            if await _already_sent(session, user.id, "deadline_72h", ref):
                continue
            hours = max(item.hours_remaining, 1)
            ok = await _deliver(
                session,
                user_id=user.id,
                tokens=devices[user.id],
                kind="deadline_72h",
                ref=ref,
                title=f"⏳ {item.exam_name}: {hours} hr{'s' if hours != 1 else ''} left",
                body=item.next_step,
                data={
                    "type": "deadline",
                    "job_post_id": ref,
                    "post_detail_id": str(item.best_post.post_detail_id),
                    "deadline": item.application_deadline.isoformat(),
                    "collapse_key": f"deadline-{ref}",
                },
                sender=sender,
                now=now,
            )
            sent += ok
    return sent


async def notify_admit_cards(
    session: AsyncSession,
    sender: Sender,
    *,
    now: datetime | None = None,
    lookback: timedelta = timedelta(days=2),
    settings: Settings | None = None,
) -> int:
    settings = settings or get_settings()
    now = now or datetime.now(UTC)
    if in_quiet_hours(now, settings):
        return 0  # admit cards are never minutes-urgent; wait for the morning
    alerts = list(
        await session.scalars(
            select(DiscoveredItem).where(
                DiscoveredItem.kind == ItemKind.ALERT,
                DiscoveredItem.status != ItemStatus.BASELINE,
                DiscoveredItem.keywords.contains(["admit_card"]),
                DiscoveredItem.created_at >= now - lookback,
            )
        )
    )
    if not alerts:
        return 0
    devices = await _devices_by_user(session)
    rows = await session.execute(
        select(User.id, JobPost.exam_name, JobPost.organization, JobPost.id)
        .join(UserApplication, UserApplication.user_id == User.profile_id)
        .join(PostDetail, PostDetail.id == UserApplication.post_detail_id)
        .join(JobPost, JobPost.id == PostDetail.job_post_id)
        .where(
            UserApplication.status == ApplicationStatus.APPLIED, User.is_active, User.id.in_(list(devices))
        )
    )
    sent = 0
    for user_id, exam_name, organization, job_id in rows.all():
        for alert in alerts:
            if not alert_matches_job(alert.title, exam_name, organization):
                continue
            ref = str(alert.id)
            if await _already_sent(session, user_id, "admit_card", ref):
                continue
            ok = await _deliver(
                session,
                user_id=user_id,
                tokens=devices[user_id],
                kind="admit_card",
                ref=ref,
                title=f"🎫 Admit card may be out: {exam_name}"[:120],
                body=alert.title,
                data={
                    "type": "admit_card",
                    "job_post_id": str(job_id),
                    "url": alert.url,
                    "collapse_key": f"admit-{job_id}",
                },
                sender=sender,
                now=now,
            )
            sent += ok
    return sent
