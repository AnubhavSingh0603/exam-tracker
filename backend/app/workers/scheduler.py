"""Background worker: `python -m app.workers.scheduler` (the `worker` service in compose).

Jobs (APScheduler 3, AsyncIOScheduler)
  crawl    every SCHEDULER_TICK_MINUTES: crawl sources whose next_check_at is due.
           Each source reschedules itself CRAWL_INTERVAL_HOURS (default 4 h) ± jitter
           after every crawl, so sources spread out instead of firing together,
           and failing sources back off exponentially (capped at 24 h).
  details  every tick: open pending aggregator detail pages to find official PDFs.
  ingest   every INGEST_INTERVAL_MINUTES: send a few PDFs to Gemini.
  purge    daily: delete expired refresh tokens.

Rate limiting: the shared Fetcher spaces requests to the same host by
PER_HOST_MIN_INTERVAL_S (+ up to 30 % jitter); different hosts run in parallel
up to CRAWL_CONCURRENCY. All jobs use coalesce + max_instances=1, so a slow run
never overlaps the next one.

Single leader: a PostgreSQL advisory lock ensures only one worker crawls, even
if two containers are started by mistake.
"""

from __future__ import annotations

import asyncio
import logging
import signal
import sys
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

import app.models  # noqa: F401  (registers tables)
from app.core.config import get_settings
from app.db.session import SessionLocal, engine
from app.services import auth_service
from app.services.discovery_pipeline import follow_detail_pages, ingest_pending_pdfs, run_due_crawls
from app.services.fcm_service import fcm_enabled, send_urgent_notification
from app.services.http_fetcher import Fetcher
from app.services.notifier import notify_admit_cards, notify_urgent_deadlines
from app.services.seeds import ensure_seed_sources

log = logging.getLogger("worker")

LEADER_LOCK_KEY = 0x45584D54  # "EXMT"


def _guarded(name: str, fn: Callable[[], Awaitable[object]]) -> Callable[[], Awaitable[None]]:
    async def run() -> None:
        started = datetime.now(UTC)
        try:
            result = await fn()
            log.info("%s finished in %.1fs (%s)", name, (datetime.now(UTC) - started).total_seconds(), result)
        except Exception:
            log.exception("%s failed", name)

    return run


def _touch_heartbeat(path: str) -> None:
    """The container healthcheck fails if this file is older than 15 minutes."""
    try:
        Path(path).write_text(datetime.now(UTC).isoformat())
    except OSError:
        log.warning("Cannot write heartbeat file %s", path)


async def _acquire_leadership() -> AsyncConnection:
    """Blocks until this process holds the advisory lock. The connection must stay open."""
    while True:
        conn = await engine.connect()
        conn = await conn.execution_options(isolation_level="AUTOCOMMIT")
        if await conn.scalar(text("SELECT pg_try_advisory_lock(:k)"), {"k": LEADER_LOCK_KEY}):
            log.info("Acquired scheduler leadership")
            return conn
        await conn.close()
        _touch_heartbeat(get_settings().worker_heartbeat_file)  # standby is healthy too
        log.info("Another worker is leader; standing by")
        await asyncio.sleep(60)


async def _wait_for_schema() -> None:
    """The API container owns schema creation; wait until its tables exist."""
    for attempt in range(60):
        try:
            async with SessionLocal() as session:
                added = await ensure_seed_sources(session)
                log.info("Seed sources ready (%d added)", added)
                return
        except Exception as exc:  # noqa: BLE001
            log.info("Waiting for database schema (%s): %s", attempt, type(exc).__name__)
            await asyncio.sleep(5)
    raise RuntimeError("Database schema never became available")


async def main() -> None:
    settings = get_settings()
    logging.basicConfig(level=settings.log_level, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    await _wait_for_schema()
    leader = await _acquire_leadership()

    fetcher = Fetcher(
        user_agent=settings.scraper_user_agent,
        timeout_s=settings.fetch_timeout_s,
        per_host_min_interval_s=settings.per_host_min_interval_s,
        respect_robots=settings.respect_robots_txt,
        extra_ca_bundle=settings.extra_ca_bundle,
        allow_legacy_tls_renegotiation=settings.tls_allow_legacy_renegotiation,
    )

    async def crawl() -> int:
        return await run_due_crawls(SessionLocal, fetcher, settings)

    async def details() -> int:
        async with SessionLocal() as session:
            return await follow_detail_pages(session, fetcher, settings)

    async def ingest() -> int:
        async with SessionLocal() as session:
            return await ingest_pending_pdfs(session, fetcher, settings)

    async def purge() -> int:
        async with SessionLocal() as session:
            return await auth_service.purge_expired_tokens(session)

    async def notify() -> str:
        async with SessionLocal() as session:
            deadlines = await notify_urgent_deadlines(session, send_urgent_notification, settings=settings)
            admit = await notify_admit_cards(session, send_urgent_notification, settings=settings)
        return f"{deadlines} deadline, {admit} admit-card pushes"

    stop = asyncio.Event()

    async def leader_heartbeat() -> None:
        try:
            await leader.scalar(text("SELECT 1"))
            _touch_heartbeat(settings.worker_heartbeat_file)
        except Exception:
            log.exception("Lost leader connection; exiting so the container restarts cleanly")
            stop.set()

    now = datetime.now(UTC)
    tick = IntervalTrigger(minutes=settings.scheduler_tick_minutes, jitter=60)
    scheduler = AsyncIOScheduler(
        timezone=settings.timezone,
        job_defaults={"coalesce": True, "max_instances": 1, "misfire_grace_time": 300},
    )
    scheduler.add_job(_guarded("crawl", crawl), tick, id="crawl", next_run_time=now + timedelta(seconds=20))
    scheduler.add_job(
        _guarded("details", details),
        IntervalTrigger(minutes=settings.scheduler_tick_minutes, jitter=60),
        id="details",
        next_run_time=now + timedelta(minutes=2),
    )
    scheduler.add_job(
        _guarded("ingest", ingest),
        IntervalTrigger(minutes=settings.ingest_interval_minutes, jitter=60),
        id="ingest",
        next_run_time=now + timedelta(minutes=4),
    )
    scheduler.add_job(_guarded("purge", purge), CronTrigger(hour=3, minute=17), id="purge")
    if fcm_enabled():
        scheduler.add_job(
            _guarded("notify", notify),
            IntervalTrigger(minutes=settings.notify_interval_minutes, jitter=60),
            id="notify",
            next_run_time=now + timedelta(minutes=6),
        )
    else:
        log.warning("FIREBASE_CREDENTIALS_FILE not configured: push notifications disabled")
    scheduler.add_job(leader_heartbeat, IntervalTrigger(minutes=5), id="leader-heartbeat")
    _touch_heartbeat(settings.worker_heartbeat_file)
    scheduler.start()
    log.info(
        "Scheduler started: tick=%sm, interval=%sh±%sm",
        settings.scheduler_tick_minutes,
        settings.crawl_interval_hours,
        settings.crawl_jitter_minutes,
    )

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:  # Windows dev machines
            pass

    try:
        await stop.wait()
    finally:
        scheduler.shutdown(wait=False)
        await fetcher.aclose()
        try:
            await leader.close()  # closing the session releases the advisory lock
        except Exception:  # noqa: BLE001
            pass
        await engine.dispose()
        log.info("Worker stopped")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
