"""One discovery run for GitHub Actions (no server needed).

    python scripts/run_pipeline.py --out ../publish

crawl due sources -> open aggregator detail pages -> read new PDFs with Gemini
-> prune old rows -> write jobs.json, notices.json and status.json into --out.

The database is a throwaway Postgres on the runner, restored from (and dumped
back to) the `data` branch by .github/workflows/data-pipeline.yml. Without
GEMINI_API_KEY the run still crawls and publishes; PDFs wait for a later run.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from sqlalchemy import delete, func, select  # noqa: E402

import app.models  # noqa: E402,F401  (registers tables)
from app.core.config import get_settings  # noqa: E402
from app.db.base import Base  # noqa: E402
from app.db.session import SessionLocal, engine  # noqa: E402
from app.domain.enums import ItemKind, ItemStatus  # noqa: E402
from app.models import DiscoveredItem, JobPost  # noqa: E402
from app.services.discovery_pipeline import (  # noqa: E402
    MAX_ATTEMPTS,
    follow_detail_pages,
    ingest_pending_pdfs,
    run_due_crawls,
)
from app.services.http_fetcher import Fetcher  # noqa: E402
from app.services.publish import SCHEMA_VERSION, build_jobs_file, build_notices_file  # noqa: E402
from app.services.seeds import ensure_seed_sources  # noqa: E402

log = logging.getLogger("pipeline")

# Kept long enough that a link seen once is never "new" again on its source.
KEEP_ITEMS = timedelta(days=365)
KEEP_JOBS = timedelta(days=400)


def gemini_configured() -> bool:
    key = get_settings().gemini_api_key.get_secret_value().strip()
    return bool(key) and key.lower() not in {"unset", "none", "changeme"}


async def pending_pdfs() -> int:
    async with SessionLocal() as session:
        return int(
            await session.scalar(
                select(func.count(DiscoveredItem.id)).where(
                    DiscoveredItem.kind == ItemKind.NOTIFICATION_PDF,
                    DiscoveredItem.status == ItemStatus.PENDING,
                    DiscoveredItem.attempts < MAX_ATTEMPTS,
                )
            )
            or 0
        )


async def prune(now: datetime) -> None:
    async with SessionLocal() as session:
        await session.execute(delete(DiscoveredItem).where(DiscoveredItem.created_at < now - KEEP_ITEMS))
        await session.execute(delete(JobPost).where(JobPost.application_deadline < now - KEEP_JOBS))
        await session.commit()


def write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    tmp.replace(path)


async def run(out: Path, ingest_rounds: int) -> dict[str, object]:
    settings = get_settings()
    started = datetime.now(UTC)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with SessionLocal() as session:
        await ensure_seed_sources(session)

    fetcher = Fetcher(
        user_agent=settings.scraper_user_agent,
        timeout_s=settings.fetch_timeout_s,
        per_host_min_interval_s=settings.per_host_min_interval_s,
        respect_robots=settings.respect_robots_txt,
        extra_ca_bundle=settings.extra_ca_bundle,
        allow_legacy_tls_renegotiation=settings.tls_allow_legacy_renegotiation,
    )
    stats: dict[str, object] = {"schema": SCHEMA_VERSION, "started_at": started.isoformat()}
    try:
        stats["sources_crawled"] = await run_due_crawls(SessionLocal, fetcher, settings)
        async with SessionLocal() as session:
            stats["detail_pages"] = await follow_detail_pages(session, fetcher, settings)

        ingested = 0
        if gemini_configured():
            # Small batches (Gemini free tier); stop early once nothing is waiting.
            for _ in range(ingest_rounds):
                if await pending_pdfs() == 0:
                    break
                async with SessionLocal() as session:
                    ingested += await ingest_pending_pdfs(session, fetcher, settings)
        else:
            log.warning("GEMINI_API_KEY not set: skipping PDF extraction this run")
        stats["pdfs_ingested"] = ingested
        stats["pdfs_waiting"] = await pending_pdfs()

        now = datetime.now(UTC)
        await prune(now)
        async with SessionLocal() as session:
            jobs = await build_jobs_file(session, now=now)
            notices = await build_notices_file(session, now=now)
    finally:
        await fetcher.aclose()
        await engine.dispose()

    write_json(out / "jobs.json", jobs)
    write_json(out / "notices.json", notices)
    stats.update(
        finished_at=datetime.now(UTC).isoformat(),
        jobs=len(jobs["jobs"]),
        notices=len(notices["notices"]),
    )
    write_json(out / "status.json", stats)
    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, required=True, help="folder for jobs.json / notices.json")
    parser.add_argument("--ingest-rounds", type=int, default=5, help="Gemini batches per run")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    stats = asyncio.run(run(args.out, args.ingest_rounds))
    log.info("Done: %s", stats)


if __name__ == "__main__":
    main()
