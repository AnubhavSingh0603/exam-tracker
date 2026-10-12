"""Phase 2: targeted, exam-centric watcher for applications the user has made.

Candidate qualifications play no part here. For each tracked exam:

  1. Primary source: fetch the exam's own portal / notice board
     (``UserApplication.official_portal_url``) and read every notice link.
  2. Secondary verification: notices the general crawl recently saw on trusted
     aggregators (``DiscoveredItem``) that name this exam.
  3. Keep notices that name this exam (or sit on an exam-specific page) and
     announce a milestone: admit card, exam date/postponement, answer key, result.
  4. Diff: a notice URL is recorded once per application (ExamUpdateLog), so
     only unseen URLs are new. New ones advance the status (never backwards),
     fill the shared 5-stage timeline, and queue a push.

Pushes go out separately (``dispatch_exam_updates``), so quiet hours can hold
them and a failed delivery is retried on the next notify run.
"""

from __future__ import annotations

import logging
import re
import uuid
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo

from dateutil import parser as dateparser
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import selectinload

from app.core.config import Settings, get_settings
from app.domain.enums import ApplicationStatus, ExamMilestone, ItemKind, ItemStatus, UpdateSource
from app.models import (
    DeviceToken,
    DiscoveredItem,
    ExamLifecycleTimeline,
    ExamUpdateLog,
    JobPost,
    User,
    UserApplication,
)
from app.services.alert_matching import alert_matches_job
from app.services.http_fetcher import Fetcher, FetchError
from app.services.notifier import Sender, deliver, in_quiet_hours
from app.services.scraper_service import Link, canonical_url, parse_generic

log = logging.getLogger(__name__)

# Results can arrive more than a year after applying; after that, stop watching.
WATCH_WINDOW = timedelta(days=548)
# Aggregator notices older than this are not "new" for anyone.
AGGREGATOR_LOOKBACK = timedelta(days=7)
# Undelivered pushes older than this are dropped (the app shows them anyway).
PUSH_EXPIRY = timedelta(days=3)

# =============================================================================
# Pure detection
# =============================================================================


def _phrases(*words: str) -> re.Pattern[str]:
    return re.compile(r"\b(?:" + "|".join(words) + r")\b", re.IGNORECASE)


# Checked in order, first match wins: the most specific / latest stage first,
# so "Result along with Final Answer Key" is a result.
MILESTONE_PATTERNS: tuple[tuple[ExamMilestone, re.Pattern[str]], ...] = (
    (ExamMilestone.POSTPONED, _phrases(r"postpone\w*", r"re-?scheduled?", r"deferred", r"cancell?ed")),
    (
        ExamMilestone.RESULT,
        _phrases(
            r"results?",
            r"merit lists?",
            r"select(?:ion)? lists?",
            r"cut[- ]?offs?",
            r"score ?cards?",
            r"final selection",
            r"marks of (?:the )?candidates",
        ),
    ),
    (
        ExamMilestone.ANSWER_KEY,
        _phrases(
            r"answer keys?",
            r"(?:provisional|tentative) keys?",
            r"response sheets?",
            r"objection\w*",
            r"question papers?",
        ),
    ),
    (
        ExamMilestone.ADMIT_CARD,
        _phrases(
            r"e-?admit cards?", r"admit cards?", r"hall tickets?", r"call letters?", r"admission certificate"
        ),
    ),
    (
        ExamMilestone.EXAM_SCHEDULE,
        _phrases(
            r"exam(?:ination)? dates?",
            r"dates? of (?:the )?exam(?:ination)?",
            r"exam(?:ination)? schedule",
            r"schedule of (?:the )?exam(?:ination)?",
            r"exam(?:ination)? calendar",
            r"exam city",
            r"city intimation",
            r"intimation slip",
            r"time ?table",
        ),
    ),
)

STATUS_FOR: Mapping[ExamMilestone, ApplicationStatus] = {
    ExamMilestone.ADMIT_CARD: ApplicationStatus.ADMIT_CARD_LIVE,
    ExamMilestone.EXAM_SCHEDULE: ApplicationStatus.EXAM_SCHEDULED,
    ExamMilestone.ANSWER_KEY: ApplicationStatus.ANSWER_KEY_LIVE,
    ExamMilestone.RESULT: ApplicationStatus.RESULT_DECLARED,
}


def classify_milestone(text: str) -> ExamMilestone | None:
    return next((m for m, pattern in MILESTONE_PATTERNS if pattern.search(text)), None)


_DATE = re.compile(
    r"\b(\d{1,2}[./-]\d{1,2}[./-](?:19|20)\d{2}"
    r"|\d{1,2}(?:st|nd|rd|th)?\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s+(?:19|20)\d{2})\b",
    re.IGNORECASE,
)


def extract_event_date(text: str) -> date | None:
    """First date printed in the notice text ("Exam on 14.12.2026" -> 2026-12-14)."""
    for m in _DATE.finditer(text):
        try:
            d = dateparser.parse(re.sub(r"(?<=\d)(st|nd|rd|th)", "", m.group(1)), dayfirst=True).date()
        except (ValueError, OverflowError):
            continue
        if 2000 <= d.year <= 2100:
            return d
    return None


_YEAR = re.compile(r"\b(20\d\d)\b")


def _years(text: str) -> set[str]:
    """Exam years named in the text; full dates (a notice's posting date) don't count."""
    return set(_YEAR.findall(_DATE.sub(" ", text)))


def names_this_exam(text: str, exam_name: str, organization: str | None) -> bool:
    """The notice is about this exam, and not about another year's edition of it."""
    exam_years, text_years = _years(exam_name), _years(text)
    if exam_years and text_years and not (exam_years & text_years):
        return False  # "SSC CGL 2025 Result" is not news for SSC CGL 2026
    return alert_matches_job(text, exam_name, organization)


def is_exam_specific_page(url: str) -> bool:
    """A recruitment's own page (".../cen-03-2026/") rather than a board's whole
    notice board: notices there may say only "Download Admit Card"."""
    path = urlsplit(url).path.strip("/")
    segments = [s for s in path.split("/") if s]
    return len(segments) >= 2 or any(ch.isdigit() for ch in path)


@dataclass(frozen=True, slots=True)
class DetectedUpdate:
    milestone: ExamMilestone
    title: str
    url: str
    source: UpdateSource
    event_date: date | None


def detect_updates(
    links: Iterable[Link],
    *,
    exam_name: str,
    organization: str | None,
    source: UpdateSource,
    exam_specific_page: bool,
    known_urls: set[str],
) -> list[DetectedUpdate]:
    """New milestone notices for one exam among a page's links (pure)."""
    found: list[DetectedUpdate] = []
    seen = set(known_urls)
    for link in links:
        url = canonical_url(link.url)
        if url in seen:
            continue
        text = f"{link.title} {link.context}".strip()
        milestone = classify_milestone(text)
        if milestone is None:
            continue
        exam_years, text_years = _years(exam_name), _years(text)
        if exam_years and text_years and not (exam_years & text_years):
            continue
        if not (exam_specific_page or names_this_exam(text, exam_name, organization)):
            continue
        seen.add(url)
        found.append(
            DetectedUpdate(
                milestone=milestone,
                title=(link.title or text)[:500],
                url=url[:2000],
                source=source,
                event_date=extract_event_date(text),
            )
        )
    return found


def advance_status(current: ApplicationStatus, milestones: Iterable[ExamMilestone]) -> ApplicationStatus:
    """Highest status the milestones imply; never moves backwards."""
    best = current
    for m in milestones:
        target = STATUS_FOR.get(m)
        if target is not None and target.rank > best.rank:
            best = target
    return best


def _fill_timeline(t: ExamLifecycleTimeline, u: DetectedUpdate, seen_on: date) -> None:
    """Newest link wins; a milestone's date is set on first sighting only."""
    text = u.title.lower()
    match u.milestone:
        case ExamMilestone.ADMIT_CARD:
            t.admit_card_url = u.url[:1000]
            t.admit_card_release = t.admit_card_release or seen_on
        case ExamMilestone.EXAM_SCHEDULE | ExamMilestone.POSTPONED:
            if "city" in text or "intimation" in text:
                t.exam_city_slip_url = u.url[:1000]
            if u.event_date is not None and u.event_date >= seen_on:
                t.exam_start = u.event_date  # a newer schedule/postponement notice wins
        case ExamMilestone.ANSWER_KEY:
            if "objection" in text or "challenge" in text:
                t.challenge_portal_url = u.url[:1000]
            elif "question paper" in text:
                t.question_paper_url = u.url[:1000]
            else:
                t.answer_key_url = u.url[:1000]
                t.answer_key_release = t.answer_key_release or seen_on
        case ExamMilestone.RESULT:
            if "score" in text:
                t.scorecard_url = u.url[:1000]
            else:
                t.merit_list_url = u.url[:1000]
            t.result_date = t.result_date or seen_on


def apply_updates(
    app: UserApplication, detected: list[DetectedUpdate], *, now: datetime, tz: ZoneInfo
) -> list[ExamUpdateLog]:
    """Record new notices on the application (and its job's shared timeline).
    Expects ``app.updates`` and, when linked, ``app.job.timeline`` to be loaded."""
    logs = [
        ExamUpdateLog(
            id=uuid.uuid4(),
            milestone=u.milestone,
            source=u.source,
            title=u.title,
            url=u.url,
            event_date=u.event_date,
            detected_at=now,
        )
        for u in detected
    ]
    if not logs:
        return []
    app.updates.extend(logs)
    app.status = advance_status(app.status, (u.milestone for u in detected))
    if app.job is not None:
        if app.job.timeline is None:
            app.job.timeline = ExamLifecycleTimeline(job_post_id=app.job.id, cutoff_marks={})
        seen_on = now.astimezone(tz).date()
        for u in detected:
            _fill_timeline(app.job.timeline, u, seen_on)
    return logs


# =============================================================================
# I/O: one application, one run
# =============================================================================


async def _portal_links(
    fetcher: Fetcher, url: str, settings: Settings, cache: dict[str, list[Link] | str]
) -> list[Link] | str:
    """Links on the page, or an error message. Each portal is fetched once per run,
    however many users track an exam on it."""
    key = canonical_url(url)
    if key not in cache:
        try:
            res = await fetcher.get(url, max_bytes=settings.max_page_bytes)
            cache[key] = [] if res.is_pdf else parse_generic(res.body, res.url)
        except FetchError as exc:
            cache[key] = f"{type(exc).__name__}: {exc}"[:300]
    return cache[key]


async def check_exam_updates(
    application: UserApplication,
    *,
    fetcher: Fetcher,
    aggregator_links: list[Link],
    portal_cache: dict[str, list[Link] | str],
    now: datetime,
    settings: Settings,
) -> list[ExamUpdateLog]:
    """Look for new milestones of one tracked exam. Mutates ``application``;
    the caller commits. Returns the new log entries (each queued for a push)."""
    known = {u.url for u in application.updates}
    detected: list[DetectedUpdate] = []
    application.last_check_error = None

    if application.official_portal_url:
        links = await _portal_links(fetcher, application.official_portal_url, settings, portal_cache)
        if isinstance(links, str):
            application.last_check_error = links
        else:
            detected += detect_updates(
                links,
                exam_name=application.exam_name,
                organization=application.organization,
                source=UpdateSource.OFFICIAL,
                exam_specific_page=is_exam_specific_page(application.official_portal_url),
                known_urls=known,
            )
    detected += detect_updates(
        aggregator_links,
        exam_name=application.exam_name,
        organization=application.organization,
        source=UpdateSource.AGGREGATOR,
        exam_specific_page=False,
        known_urls=known | {u.url for u in detected},
    )
    application.last_checked_at = now
    return apply_updates(application, detected, now=now, tz=ZoneInfo(settings.timezone))


async def _recent_aggregator_links(session: AsyncSession, now: datetime) -> list[Link]:
    items = await session.scalars(
        select(DiscoveredItem).where(
            DiscoveredItem.kind.in_([ItemKind.ALERT, ItemKind.OTHER]),
            DiscoveredItem.status != ItemStatus.BASELINE,
            DiscoveredItem.created_at >= now - AGGREGATOR_LOOKBACK,
        )
    )
    return [Link(url=i.url, title=i.title) for i in items]


async def run_exam_watch(
    session_factory: async_sessionmaker[AsyncSession],
    fetcher: Fetcher,
    settings: Settings | None = None,
    *,
    now: datetime | None = None,
) -> str:
    """Check every tracked exam that is due (last checked > interval ago)."""
    settings = settings or get_settings()
    now = now or datetime.now(UTC)
    due_before = now - timedelta(hours=settings.exam_watch_interval_hours)
    async with session_factory() as session:
        apps = (
            await session.scalars(
                select(UserApplication)
                .where(
                    UserApplication.status.notin_(
                        [ApplicationStatus.DISCOVERED, ApplicationStatus.RESULT_DECLARED]
                    ),
                    UserApplication.created_at >= now - WATCH_WINDOW,
                    or_(
                        UserApplication.last_checked_at.is_(None),
                        UserApplication.last_checked_at < due_before,
                    ),
                )
                .options(
                    selectinload(UserApplication.updates),
                    selectinload(UserApplication.job).selectinload(JobPost.timeline),
                )
            )
        ).all()
        if not apps:
            return "0 exams due"
        aggregator_links = await _recent_aggregator_links(session, now)
        cache: dict[str, list[Link] | str] = {}
        found = 0
        for app in apps:
            try:
                found += len(
                    await check_exam_updates(
                        app,
                        fetcher=fetcher,
                        aggregator_links=aggregator_links,
                        portal_cache=cache,
                        now=now,
                        settings=settings,
                    )
                )
                await session.commit()
            except Exception:  # one bad exam must not stop the others
                log.exception("Exam watch failed for application %s", app.id)
                await session.rollback()
    return f"{len(apps)} exams checked, {found} new updates"


# =============================================================================
# Delivery
# =============================================================================

_PUSH_TEXT: Mapping[ExamMilestone, tuple[str, str]] = {
    ExamMilestone.ADMIT_CARD: (
        "🎫 Admit card out: {exam}",
        "Download it now — portals often close it before the exam.",
    ),
    ExamMilestone.EXAM_SCHEDULE: ("📅 Exam date update: {exam}", "{title}"),
    ExamMilestone.POSTPONED: ("⚠️ Exam rescheduled: {exam}", "{title}"),
    ExamMilestone.ANSWER_KEY: (
        "📝 Answer key released: {exam}",
        "Check your answers; objections have a deadline.",
    ),
    ExamMilestone.RESULT: ("🏁 Result declared: {exam}", "{title}"),
}


def push_text(log_entry: ExamUpdateLog, exam_name: str) -> tuple[str, str]:
    title, body = _PUSH_TEXT[log_entry.milestone]
    return title.format(exam=exam_name)[:120], body.format(title=log_entry.title)[:240]


async def dispatch_exam_updates(
    session: AsyncSession,
    sender: Sender,
    *,
    now: datetime | None = None,
    settings: Settings | None = None,
) -> int:
    """Push queued watcher updates (high priority). Held during quiet hours."""
    settings = settings or get_settings()
    now = now or datetime.now(UTC)
    if in_quiet_hours(now, settings):
        return 0
    rows = (
        await session.execute(
            select(ExamUpdateLog, UserApplication, User.id)
            .join(UserApplication, UserApplication.id == ExamUpdateLog.application_id)
            .join(User, User.profile_id == UserApplication.user_id)
            .where(
                ExamUpdateLog.notified_at.is_(None),
                ExamUpdateLog.detected_at >= now - PUSH_EXPIRY,
                User.is_active,
            )
            .order_by(ExamUpdateLog.detected_at)
        )
    ).all()
    if not rows:
        return 0
    user_ids = list({user_id for *_, user_id in rows})
    tokens: dict[uuid.UUID, list[DeviceToken]] = {}
    for device in await session.scalars(select(DeviceToken).where(DeviceToken.user_id.in_(user_ids))):
        tokens.setdefault(device.user_id, []).append(device)

    sent = 0
    for entry, app, user_id in rows:
        devices = tokens.get(user_id)
        if not devices:
            entry.notify_error = "no registered device"
            continue
        title, body = push_text(entry, app.exam_name)
        ok = await deliver(
            session,
            user_id=user_id,
            tokens=devices,
            kind="exam_update",
            ref=str(entry.id),
            title=title,
            body=body,
            data={
                "type": "exam_update",
                "application_id": str(app.id),
                "milestone": entry.milestone.value,
                "url": entry.url,
                "collapse_key": f"exam-{app.id}-{entry.milestone.value}",
            },
            sender=sender,
            now=now,
        )
        if ok:
            entry.notified_at, entry.notify_error = now, None
            sent += 1
        else:
            entry.notify_error = "delivery failed; will retry"
    await session.commit()
    return sent
