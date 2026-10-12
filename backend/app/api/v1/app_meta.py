"""Public release metadata for the in-app updater (direct/GitHub builds only)."""

import json
import logging
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Response, status
from pydantic import ValidationError

from app.core.config import get_settings
from app.schemas.app_meta import AppVersionOut, ReleaseManifest

router = APIRouter(prefix="/app", tags=["app"])
log = logging.getLogger(__name__)

_cache: tuple[float, ReleaseManifest] | None = None


def load_manifest(path: str) -> ReleaseManifest:
    """Re-reads the file only when it changes, so CI can update it without a restart."""
    global _cache
    p = Path(path)
    try:
        mtime = p.stat().st_mtime
    except FileNotFoundError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No release published yet") from None
    if _cache is not None and _cache[0] == mtime:
        return _cache[1]
    try:
        manifest = ReleaseManifest.model_validate(json.loads(p.read_text(encoding="utf-8")))
    except (ValueError, ValidationError) as exc:
        log.error("Invalid release manifest %s: %s", path, exc)
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Release manifest is invalid") from exc
    _cache = (mtime, manifest)
    return manifest


@router.get("/version", response_model=AppVersionOut)
async def latest_version(
    response: Response,
    current_version_code: Annotated[int | None, Query(ge=1)] = None,
    abi: Annotated[str | None, Query(max_length=20, description="Device primary ABI, e.g. arm64-v8a")] = None,
) -> AppVersionOut:
    manifest = load_manifest(get_settings().release_manifest_path)
    chosen = abi if abi and abi in manifest.apks else "universal"
    asset = manifest.apks[chosen]
    response.headers["Cache-Control"] = "public, max-age=300"
    out = AppVersionOut(
        latest_version_code=manifest.version_code,
        version_name=manifest.version_name,
        min_supported_version_code=manifest.min_supported_version_code,
        release_notes=manifest.release_notes,
        published_at=manifest.published_at,
        apk_url=str(asset.url),
        sha256=asset.sha256,
        size_bytes=asset.size_bytes,
        abi=chosen,
    )
    if current_version_code is not None:
        out.update_available = manifest.version_code > current_version_code
        out.mandatory = current_version_code < manifest.min_supported_version_code
    return out
