"""Orchestration used by the scheduler: crawl due sources, open aggregator
detail pages, and push discovered PDFs through the Phase 1 Gemini ingester."""

from __future__ import annotations

import asyncio
import logging
import uuid
from collections import defaultdict
from collections.abc import Callable
from datetime import UTC, datetime
from urllib.parse import urlsplit

from sqlalchemy import or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.domain.enums import ItemKind, ItemStatus
from app.models import DiscoveredItem, Source
from app.services.http_fetcher import Fetcher, FetchError, RetryableFetchError
from app.services.ingestion import ingest_notification
from app.services.pdf_parser import ExtractionError, GeminiQuotaExhausted
from app.services.scraper_service import DETAIL_PARSERS, SourceCrawler, classify

log = logging.getLogger(__name__)

SessionFactory = Callable[[], AsyncSession]
MAX_ATTEMPTS = 3


# -----------------------------------------------------------------------------
# 1. Crawl due sources (different hosts in parallel, same host sequential)
# -----------------------------------------------------------------------------


async def run_due_crawls(
    session_factory: SessionFactory, fetcher: Fetcher, settings: Settings | None = None
) -> int:
    settings = settings or get_settings()
    now = datetime.now(UTC)
    async with session_factory() as session:
        due = (
            await session.execute(
                select(Source.id, Source.url)
                .where(Source.enabled, or_(Source.next_check_at.is_(None), Source.next_check_at <= now))
                .order_by(Source.next_check_at.asc().nulls_first())
                .limit(100)
            )
        ).all()
    if not due:
        return 0

    by_host: defaultdict[str, list[uuid.UUID]] = defaultdict(list)
    for source_id, url in due:
        by_host[urlsplit(url).hostname or ""].append(source_id)

    crawler = SourceCrawler(fetcher, settings)
    sem = asyncio.Semaphore(settings.crawl_concurrency)

    async def crawl_host(ids: list[uuid.UUID]) -> None:
        async with sem:
            for source_id in ids:
                async with session_factory() as session:
                    source = await session.get(Source, source_id)
                    if source is not None and source.enabled:
                        await crawler.crawl(session, source)

    await asyncio.gather(*(crawl_host(ids) for ids in by_host.values()))
    return len(due)


# -----------------------------------------------------------------------------
# 2. Aggregator detail pages -> official notification PDF links
# -----------------------------------------------------------------------------


async def follow_detail_pages(
    session: AsyncSession, fetcher: Fetcher, settings: Settings | None = None
) -> int:
    settings = settings or get_settings()
    items = list(
        await session.scalars(
            select(DiscoveredItem)
            .join(Source)
            .where(DiscoveredItem.kind == ItemKind.DETAIL_PAGE, DiscoveredItem.status == ItemStatus.PENDING)
            .order_by(DiscoveredItem.created_at)
            .limit(settings.aggregator_detail_pages_per_run)
        )
    )
    processed = 0
    for item in items:
        source = await session.get(Source, item.source_id)
        parse = DETAIL_PARSERS.get(source.parser) if source else None
        if parse is None:
            item.status = ItemStatus.SKIPPED
            continue
        item.attempts += 1
        try:
            res = await fetcher.get(item.url, max_bytes=settings.max_page_bytes)
        except FetchError as exc:
            _record_failure(item, exc, retryable=isinstance(exc, RetryableFetchError))
            await session.commit()
            continue

        rows = []
        for link in parse(res.body, res.url):
            kind, flags = classify(link)
            if kind is ItemKind.OTHER:
                kind = ItemKind.NOTIFICATION_PDF  # the detail parser already picked the notification row
            rows.append(
                {
                    "id": uuid.uuid4(),
                    "attempts": 0,
                    "source_id": item.source_id,
                    "url": link.url[:2000],
                    "title": (link.title or item.title)[:500],
                    "kind": kind,
                    "status": ItemStatus.PENDING if kind is ItemKind.NOTIFICATION_PDF else ItemStatus.DONE,
                    "keywords": flags,
                    "published_at": item.published_at,
                }
            )
        if rows:
            await session.execute(
                pg_insert(DiscoveredItem)
                .values(rows)
                .on_conflict_do_nothing(index_elements=["source_id", "url"])
            )
        item.status = ItemStatus.DONE
        item.error = None if rows else "No notification link found on page"
        await session.commit()
        processed += 1
    await session.commit()
    return processed


# -----------------------------------------------------------------------------
# 3. Notification PDFs -> Gemini -> job_posts (Phase 1 ingester)
# -----------------------------------------------------------------------------


async def ingest_pending_pdfs(
    session: AsyncSession, fetcher: Fetcher, settings: Settings | None = None
) -> int:
    """Small batches on purpose: the Gemini free tier is rate-limited per minute and per day."""
    settings = settings or get_settings()
    items = list(
        await session.scalars(
            select(DiscoveredItem)
            .where(
                DiscoveredItem.kind == ItemKind.NOTIFICATION_PDF,
                DiscoveredItem.status == ItemStatus.PENDING,
                DiscoveredItem.attempts < MAX_ATTEMPTS,
            )
            .order_by(DiscoveredItem.published_at.desc().nulls_last(), DiscoveredItem.created_at.desc())
            .limit(settings.ingest_batch_size)
        )
    )
    done = 0
    for item in items:
        item_id, url = item.id, item.url
        item.attempts += 1
        await session.commit()
        try:
            res = await fetcher.get(url, max_bytes=settings.max_upload_bytes)
            if not res.is_pdf:
                await _finish(session, item_id, ItemStatus.SKIPPED, error="Link is not a PDF")
                continue
            job, created = await ingest_notification(session, res.body)
        except GeminiQuotaExhausted:
            # Not this PDF's fault: back in the queue untouched, and stop for this run.
            item = await session.get(DiscoveredItem, item_id)
            if item is not None:
                return_to_queue(item)
                await session.commit()
            raise
        except ExtractionError as exc:
            await _finish(session, item_id, ItemStatus.FAILED, error=f"Extraction: {exc}")
            continue
        except FetchError as exc:
            retry = isinstance(exc, RetryableFetchError)
            item = await session.get(DiscoveredItem, item_id)
            if item is not None:
                _record_failure(item, exc, retryable=retry)
                await session.commit()
            continue
        await _finish(session, item_id, ItemStatus.DONE, job_post_id=job.id)
        done += 1
        log.info("Ingested %s -> %s (%s)", url, job.exam_name, "new" if created else "duplicate")
    return done


def return_to_queue(item: DiscoveredItem) -> None:
    """Undo an attempt that failed for reasons outside the item (e.g. Gemini quota)."""
    item.status = ItemStatus.PENDING
    item.attempts = max(0, item.attempts - 1)
    item.error = None


def _record_failure(item: DiscoveredItem, exc: Exception, *, retryable: bool) -> None:
    item.error = str(exc)[:1000]
    if not retryable or item.attempts >= MAX_ATTEMPTS:
        item.status = ItemStatus.FAILED


async def _finish(
    session: AsyncSession,
    item_id: uuid.UUID,
    status: ItemStatus,
    *,
    error: str | None = None,
    job_post_id: uuid.UUID | None = None,
) -> None:
    # Re-load: ingest_notification may have rolled the session back.
    item = await session.get(DiscoveredItem, item_id)
    if item is None:
        return
    item.status = status
    item.error = error
    if job_post_id is not None:
        item.job_post_id = job_post_id
    await session.commit()
