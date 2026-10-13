"""PDF -> Gemini -> PostgreSQL. Idempotent on the PDF's SHA-256."""

from __future__ import annotations

import asyncio
import hashlib
import logging
import uuid
from pathlib import Path

from sqlalchemy import ColumnElement, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
from app.models import ExamLifecycleTimeline, JobPost, PostDetail, VacancyMatrix
from app.schemas.notification import ParsedNotification
from app.services.pdf_parser import extract_notification

log = logging.getLogger(__name__)


async def load_job(session: AsyncSession, where: ColumnElement[bool]) -> JobPost | None:
    stmt = (
        select(JobPost)
        .where(where)
        .options(
            selectinload(JobPost.posts).selectinload(PostDetail.vacancy),
            selectinload(JobPost.timeline),
        )
        .execution_options(populate_existing=True)
    )
    return await session.scalar(stmt)


def _write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".{uuid.uuid4().hex}.tmp")
    tmp.write_bytes(data)
    tmp.replace(path)


def _to_orm(parsed: ParsedNotification, *, sha256: str, pdf_path: str, model: str) -> JobPost:
    return JobPost(
        organization=parsed.organization,
        exam_name=parsed.exam_name,
        advertisement_no=parsed.advertisement_no,
        portal_url=parsed.portal_url,
        application_start=parsed.application_start,
        application_deadline=parsed.application_deadline,
        exam_date=parsed.exam_date,
        source_pdf_sha256=sha256,
        source_pdf_path=pdf_path,
        extraction_model=model,
        needs_review=parsed.needs_review,
        review_notes=parsed.review_notes,
        posts=[
            PostDetail(
                post_code=p.post_code,
                post_name=p.post_name,
                min_age=p.min_age,
                base_max_age=p.base_max_age,
                age_as_on=p.age_as_on,
                eligible_streams=p.eligible_streams,
                qualification_text=p.qualification_text,
                age_relaxation_overrides=p.age_relaxation_overrides,
                allowed_degrees=p.allowed_degrees,
                raw_eligibility_text=p.raw_eligibility_text,
                min_qualification_level=p.min_qualification_level,
                is_open_to_any_graduate=p.is_open_to_any_graduate,
                is_open_to_any_post_graduate=p.is_open_to_any_post_graduate,
                min_experience_years=p.min_experience_years,
                vacancy=VacancyMatrix(**p.vacancy.model_dump()),
            )
            for p in parsed.posts
        ],
        timeline=ExamLifecycleTimeline(**parsed.timeline.model_dump()),
    )


async def ingest_notification(
    session: AsyncSession,
    data: bytes,
    *,
    portal_url_override: str | None = None,
) -> tuple[JobPost, bool]:
    """Returns ``(job, created)``. Raises ``ExtractionError`` if Gemini can't parse it."""
    settings = get_settings()
    sha256 = hashlib.sha256(data).hexdigest()

    if existing := await load_job(session, JobPost.source_pdf_sha256 == sha256):
        return existing, False

    parsed = await extract_notification(data)
    if portal_url_override:
        parsed.portal_url = portal_url_override

    pdf_path = settings.upload_dir / f"{sha256}.pdf"
    await asyncio.to_thread(_write_atomic, pdf_path, data)

    model = parsed.extraction_model or settings.gemini_model
    job = _to_orm(parsed, sha256=sha256, pdf_path=str(pdf_path), model=model)
    session.add(job)
    try:
        await session.commit()
    except IntegrityError:
        # A concurrent upload of the same PDF won the race.
        await session.rollback()
        existing = await load_job(session, JobPost.source_pdf_sha256 == sha256)
        if existing is None:
            raise
        return existing, False

    log.info("Ingested %s (%d posts, needs_review=%s)", job.exam_name, len(job.posts), job.needs_review)
    loaded = await load_job(session, JobPost.id == job.id)
    assert loaded is not None
    return loaded, True
