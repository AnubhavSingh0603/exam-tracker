import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

import app.models  # noqa: F401  (registers tables)
from app.api.v1 import api_router
from app.core.config import get_settings
from app.db.base import Base
from app.db.session import engine
from app.services.http_fetcher import Fetcher

settings = get_settings()
logging.basicConfig(level=settings.log_level, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(app_: FastAPI) -> AsyncIterator[None]:
    if settings.auto_create_schema:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
    # Used for source previews; the worker process has its own.
    app_.state.fetcher = Fetcher(
        user_agent=settings.scraper_user_agent,
        timeout_s=settings.fetch_timeout_s,
        per_host_min_interval_s=2.0,  # one-off previews, not a crawl
        respect_robots=settings.respect_robots_txt,
        extra_ca_bundle=settings.extra_ca_bundle,
        allow_legacy_tls_renegotiation=settings.tls_allow_legacy_renegotiation,
        attempts=1,
    )
    yield
    await app_.state.fetcher.aclose()
    await engine.dispose()


app = FastAPI(
    title="Exam Tracker API",
    version="0.3.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.environment == "dev" else None,
    redoc_url=None,
)

if settings.cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["Authorization", "X-API-Key", "Content-Type"],
    )

app.include_router(api_router)


@app.get("/healthz", include_in_schema=False)
async def healthz() -> JSONResponse:
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
    except Exception:  # noqa: BLE001
        return JSONResponse({"status": "degraded", "db": False}, status_code=503)
    return JSONResponse({"status": "ok", "db": True})
