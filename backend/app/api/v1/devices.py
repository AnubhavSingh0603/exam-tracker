from fastapi import APIRouter, status
from pydantic import BaseModel, Field
from sqlalchemy import delete, select

from app.api.deps import CurrentUser, SessionDep
from app.models import DeviceToken

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
