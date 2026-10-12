"""Personalised, urgency-sorted, deliberately short feed."""

from __future__ import annotations

from datetime import UTC, datetime
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
from app.domain.enums import ApplicationStatus, UrgencyBand
from app.models import JobPost, PostDetail, UserApplication, UserProfile
from app.schemas.feed import FeedItem, FeedPost, FeedResponse
from app.services.eligibility import EligibilityResult, evaluate_eligibility

CRITICAL_HOURS = 72
APPROACHING_DAYS = 14


def urgency_for(deadline: datetime, now: datetime) -> tuple[UrgencyBand, int]:
    hours = int((deadline - now).total_seconds() // 3600)
    if hours < CRITICAL_HOURS:
        return UrgencyBand.CRITICAL, hours
    if hours <= APPROACHING_DAYS * 24:
        return UrgencyBand.APPROACHING, hours
    return UrgencyBand.SAFE, hours


def _feed_post(post: PostDetail, r: EligibilityResult) -> FeedPost:
    return FeedPost(
        post_detail_id=post.id,
        post_code=post.post_code,
        post_name=post.post_name,
        age_on_cutoff_years=r.age_on_cutoff.years if r.age_on_cutoff else None,
        effective_max_age=r.effective_max_age,
        eligible_via_relaxation=r.eligible_via_relaxation,
        category_quota_seats=r.category_quota_seats,
        ur_open_seats=r.ur_open_seats,
        total_reachable_seats=r.total_reachable_seats,
        qualification_verified=r.qualification_match is True,
        notes=list(r.reasons),
    )


def _next_step(job: JobPost, best: FeedPost, deadline: datetime, tz: ZoneInfo) -> str:
    local = deadline.astimezone(tz)
    when = f"{local:%a} {local.day} {local:%b}, {local:%I:%M %p}"
    return f"Apply for {best.post_name} ({job.organization}) — closes {when}"


async def _applied_post_ids(session: AsyncSession, user: UserProfile) -> set:
    rows = await session.scalars(
        select(UserApplication.post_detail_id).where(
            UserApplication.user_id == user.id,
            UserApplication.status != ApplicationStatus.DISCOVERED,
        )
    )
    return set(rows)


async def build_feed(
    session: AsyncSession,
    user: UserProfile,
    *,
    now: datetime | None = None,
    limit: int | None = None,
) -> FeedResponse:
    settings = get_settings()
    tz = ZoneInfo(settings.timezone)
    now = now or datetime.now(UTC)
    limit = max(1, min(limit or settings.feed_max_items, settings.feed_max_items))

    jobs = (
        await session.scalars(
            select(JobPost)
            .where(JobPost.application_deadline > now)
            .order_by(JobPost.application_deadline.asc(), JobPost.id)
            .limit(settings.feed_scan_limit)
            .options(selectinload(JobPost.posts).selectinload(PostDetail.vacancy))
        )
    ).all()
    already_applied = await _applied_post_ids(session, user)

    items: list[FeedItem] = []
    for job in jobs:  # already in strict deadline order
        eligible: list[FeedPost] = []
        for post in job.posts:
            if post.id in already_applied:
                continue
            try:
                result = evaluate_eligibility(user, post, strict_ur_migration=settings.strict_ur_migration)
            except ValueError:  # DOB after cut-off: corrupt data, never eligible
                continue
            if result.is_eligible:
                eligible.append(_feed_post(post, result))
        if not eligible:
            continue
        eligible.sort(key=lambda p: p.total_reachable_seats, reverse=True)
        deadline = job.application_deadline
        assert deadline is not None  # guaranteed by the WHERE clause
        band, hours = urgency_for(deadline, now)
        items.append(
            FeedItem(
                job_post_id=job.id,
                organization=job.organization,
                exam_name=job.exam_name,
                portal_url=job.portal_url,
                application_deadline=deadline,
                hours_remaining=hours,
                urgency=band,
                next_step=_next_step(job, eligible[0], deadline, tz),
                best_post=eligible[0],
                other_eligible_posts=eligible[1:],
            )
        )

    shown = items[:limit]
    return FeedResponse(
        generated_at=now,
        category=user.category,
        hero=shown[0] if shown else None,
        up_next=shown[1:],
        hidden_count=len(items) - len(shown),
    )
