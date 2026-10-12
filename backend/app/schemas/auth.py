import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class GoogleLoginIn(BaseModel):
    id_token: str = Field(min_length=20, max_length=4096)


class RefreshIn(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=2048)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    name: str | None
    picture_url: str | None
    profile_id: uuid.UUID | None


class TokenOut(BaseModel):
    token_type: str = "bearer"
    access_token: str
    access_expires_at: datetime
    refresh_token: str
    refresh_expires_at: datetime
    user: UserOut
    is_new_user: bool = False
    needs_profile: bool = Field(description="True until DOB/category/streams are saved")
