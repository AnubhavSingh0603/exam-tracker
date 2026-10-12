import uuid

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import delete, select

from app.api.deps import CurrentUser, SessionDep
from app.domain.enums import ApplicationStatus
from app.models import DeviceToken, PostDetail, UserApplication

router = APIRouter(tags=["devices"])


class DeviceIn(BaseModel):
    token: str = Field(min_length=20, max_length=512)
    kind: str = Field(
        "token", pattern="^(token|fid)$", description="FCM registration token or installation ID"
    )
    platform: str = Field("android", pattern="^(android)$")
    app_version_code: int | None = Field(None, ge=1)


class DeviceTokenRef(BaseModel):
    token: str = Field(min_length=20, max_length=512)


@router.put("/devices", status_code=status.HTTP_204_NO_CONTENT)
async def register_device(body: DeviceIn, user: CurrentUser, session: SessionDep) -> None:
    """Call on every app start and whenever FCM rotates the token. Idempotent."""
    device = await session.scalar(select(DeviceToken).where(DeviceToken.token == body.token))
    if device is None:
        session.add(
            DeviceToken(
                user_id=user.id,
                token=body.token,
                kind=body.kind,
                platform=body.platform,
                app_version_code=body.app_version_code,
            )
        )
    else:
        # Same phone, different account (sign-out/sign-in): the token follows the user.
        device.user_id = user.id
        device.kind = body.kind
        device.app_version_code = body.app_version_code
        device.failures = 0
    await session.commit()


@router.delete("/devices", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_device(body: DeviceTokenRef, user: CurrentUser, session: SessionDep) -> None:
    await session.execute(
        delete(DeviceToken).where(DeviceToken.token == body.token, DeviceToken.user_id == user.id)
    )
    await session.commit()


# --- Application status: lets the server stop pinging about jobs you applied to ---


class ApplicationIn(BaseModel):
    status: ApplicationStatus


@router.put("/applications/{post_detail_id}", status_code=status.HTTP_204_NO_CONTENT)
async def upsert_application(
    post_detail_id: uuid.UUID, body: ApplicationIn, user: CurrentUser, session: SessionDep
) -> None:
    if user.profile_id is None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Create your profile first")
    if await session.get(PostDetail, post_detail_id) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Unknown post")
    app = await session.scalar(
        select(UserApplication).where(
            UserApplication.user_id == user.profile_id, UserApplication.post_detail_id == post_detail_id
        )
    )
    if app is None:
        session.add(
            UserApplication(user_id=user.profile_id, post_detail_id=post_detail_id, status=body.status)
        )
    else:
        app.status = body.status
    await session.commit()


@router.delete("/applications/{post_detail_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_application(post_detail_id: uuid.UUID, user: CurrentUser, session: SessionDep) -> None:
    if user.profile_id is not None:
        await session.execute(
            delete(UserApplication).where(
                UserApplication.user_id == user.profile_id, UserApplication.post_detail_id == post_detail_id
            )
        )
        await session.commit()
