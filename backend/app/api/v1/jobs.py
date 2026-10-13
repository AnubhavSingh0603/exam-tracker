import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile, status
from pydantic import HttpUrl

from app.api.deps import PrincipalDep, SessionDep, require_api_key
from app.core.config import get_settings
from app.models import UserProfile
from app.schemas.feed import FeedResponse
from app.schemas.job import JobPostOut, UploadResult
from app.services.feed import build_feed
from app.services.ingestion import ingest_notification
from app.services.lifecycle import timeline_out
from app.services.pdf_parser import ExtractionError

router = APIRouter(prefix="/jobs", tags=["jobs"])

_CHUNK = 1024 * 1024


async def _read_limited(upload: UploadFile, max_bytes: int) -> bytes:
    buf = bytearray()
    while chunk := await upload.read(_CHUNK):
        buf.extend(chunk)
        if len(buf) > max_bytes:
            raise HTTPException(
                status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                f"PDF exceeds {max_bytes // (1024 * 1024)} MB",
            )
    return bytes(buf)


@router.post(
    "/upload-notification",
    response_model=UploadResult,
    status_code=status.HTTP_201_CREATED,
    responses={200: {"description": "PDF already ingested; existing record returned"}},
    dependencies=[Depends(require_api_key)],  # Gemini quota is the owner's: admin only
)
async def upload_notification(
    response: Response,
    session: SessionDep,
    file: Annotated[UploadFile, File(description="Official notification PDF")],
    portal_url: Annotated[HttpUrl | None, Form()] = None,
) -> UploadResult:
    data = await _read_limited(file, get_settings().max_upload_bytes)
    if not data.startswith(b"%PDF-"):
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "File is not a PDF")

    try:
        job, created = await ingest_notification(
            session, data, portal_url_override=str(portal_url) if portal_url else None
        )
    except ExtractionError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, f"Extraction failed: {exc}") from exc

    if not created:
        response.status_code = status.HTTP_200_OK
    out = JobPostOut.model_validate(job).model_copy(update={"timeline": timeline_out(job)})
    return UploadResult(created=created, job=out)


@router.get("/feed", response_model=FeedResponse)
async def get_feed(
    session: SessionDep,
    principal: PrincipalDep,
    user_id: Annotated[uuid.UUID | None, Query(description="Admin (X-API-Key) only")] = None,
    limit: Annotated[int | None, Query(ge=1, description="Clamped to FEED_MAX_ITEMS (≤5)")] = None,
) -> FeedResponse:
    if principal.user is not None:
        profile = principal.user.profile
        if profile is None:
            raise HTTPException(
                status.HTTP_409_CONFLICT, "Create your profile first: PUT /api/v1/users/me/profile"
            )
    else:
        if user_id is None:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "user_id is required with X-API-Key")
        profile = await session.get(UserProfile, user_id)
        if profile is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    return await build_feed(session, profile, limit=limit)
