"""Decides *who* gets pinged about *what*, then hands off to FCM.

Triggers, each sent at most once per user (NotificationLog):
  deadline_72h  a job in the user's eligible feed closes in < URGENT_DEADLINE_HOURS
                (the feed already excludes jobs the user marked Applied)
  exam_update   a new milestone of an exam the user applied to
                (detected and queued by services/exam_watcher.py)

ADHD-friendly restraint: quiet hours (default 22:00–07:00 local) hold back pings
unless a deadline is under QUIET_HOURS_OVERRIDE_HOURS. Held pings go out on the
first run after quiet hours, because nothing is logged until delivery succeeds.
"""

from __future__ import annotations

import logging
import uuid
from collections import defaultdict
from collections.abc import Awaitable
from datetime import UTC, datetime
from typing import Protocol
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.models import (
    DeviceToken,
    NotificationLog,
    User,
)
from app.services.alert_matching import alert_matches_job
from app.services.fcm_service import SendResult
from app.services.feed import build_feed

__all__ = ["alert_matches_job", "in_quiet_hours"]

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


async def deliver(
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
            ok = await deliver(
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
