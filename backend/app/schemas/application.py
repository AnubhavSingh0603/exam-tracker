import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, HttpUrl

from app.domain.enums import ApplicationStatus, ExamMilestone, UpdateSource
from app.schemas.lifecycle import LifecycleTimelineOut


class ApplicationStatusIn(BaseModel):
    status: ApplicationStatus


class ManualApplicationIn(BaseModel):
    """An exam applied to outside the feed: the watcher follows its portal."""

    exam_name: str = Field(min_length=3, max_length=300, examples=["SSC CGL 2026"])
    official_portal_url: HttpUrl | None = Field(None, examples=["https://ssc.gov.in/"])
    organization: str | None = Field(None, max_length=200, examples=["Staff Selection Commission"])


class ExamUpdateOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    milestone: ExamMilestone
    source: UpdateSource
    title: str
    url: str
    event_date: date | None
    detected_at: datetime


class ApplicationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    post_detail_id: uuid.UUID | None
    job_id: uuid.UUID | None
    exam_name: str
    organization: str | None
    official_portal_url: str | None
    status: ApplicationStatus
    last_checked_at: datetime | None
    last_check_error: str | None
    updates: list[ExamUpdateOut] = Field(description="Newest first, at most 20")
    timeline: LifecycleTimelineOut | None = None
