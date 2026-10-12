import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, HttpUrl

from app.domain.enums import ItemKind, ParserKey, SourceKind


class CustomUrlIn(BaseModel):
    url: HttpUrl
    name: str | None = Field(None, max_length=200)


class TelegramIn(BaseModel):
    channel: str = Field(
        min_length=4, max_length=100, examples=["@sarkari_naukri_alerts", "https://t.me/s/xyz"]
    )


class SourceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    kind: SourceKind
    parser: ParserKey
    name: str
    url: str
    enabled: bool
    is_mine: bool = False
    last_checked_at: datetime | None
    last_changed_at: datetime | None
    next_check_at: datetime | None
    last_error: str | None


class SourcePreview(BaseModel):
    links_found: int
    notification_candidates: int
    alerts: int
    sample: list[str] = Field(description="Up to 5 titles that look like notifications or alerts")


class SourceCreated(BaseModel):
    source: SourceOut
    already_tracked: bool
    preview: SourcePreview | None


class AlertOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    url: str
    kind: ItemKind
    keywords: list[str]
    published_at: datetime | None
    created_at: datetime
    source_name: str
