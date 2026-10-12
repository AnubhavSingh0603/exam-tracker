import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict

from app.domain.qualifications import QualificationLevel
from app.schemas.lifecycle import LifecycleTimelineOut


class _ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class VacancyOut(_ORM):
    ur: int
    sc: int
    st: int
    obc: int
    ews: int
    total: int
    pwbd: int | None
    ex_serviceman: int | None


class PostDetailOut(_ORM):
    id: uuid.UUID
    post_code: str | None
    post_name: str
    min_age: int | None
    base_max_age: int | None
    age_as_on: date | None
    eligible_streams: list[str]
    qualification_text: str | None
    allowed_degrees: list[str]
    raw_eligibility_text: str | None
    min_qualification_level: QualificationLevel | None
    is_open_to_any_graduate: bool
    is_open_to_any_post_graduate: bool
    min_experience_years: float
    age_relaxation_overrides: dict[str, int]
    vacancy: VacancyOut | None


class JobPostOut(_ORM):
    id: uuid.UUID
    organization: str
    exam_name: str
    advertisement_no: str | None
    portal_url: str | None
    application_start: datetime | None
    application_deadline: datetime | None
    exam_date: date | None
    needs_review: bool
    review_notes: list[str]
    posts: list[PostDetailOut]
    timeline: LifecycleTimelineOut | None = None  # filled by the route (needs job dates too)


class UploadResult(BaseModel):
    created: bool  # False => identical PDF was already ingested
    job: JobPostOut
