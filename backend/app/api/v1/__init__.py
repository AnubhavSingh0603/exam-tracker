from fastapi import APIRouter

from app.api.v1 import app_meta, auth, devices, jobs, sources, users

# Auth is per-route now: /auth is public, others take a Bearer token and/or X-API-Key.
api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth.router)
api_router.include_router(jobs.router)
api_router.include_router(users.router)
api_router.include_router(sources.router)
api_router.include_router(devices.router)
api_router.include_router(app_meta.router)
