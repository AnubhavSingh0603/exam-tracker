import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field


class LifecycleTimelineOut(BaseModel):
    """The 5 post-application milestones of one notification. Every field is
    optional: notifications announce them gradually, and the phone shows
    whatever is known (stage progress is computed on the device)."""

    model_config = ConfigDict(from_attributes=True)

    job_post_id: uuid.UUID
    # 1. Application window (start/end copied from the job post)
    application_start: datetime | None = None
    application_end: datetime | None = None
    fee_deadline: date | None = None
    edit_window_start: date | None = None
    edit_window_end: date | None = None
    # 2. Admit card
    admit_card_release: date | None = None
    admit_card_url: str | None = None
    # 3. Exam
    exam_start: date | None = None
    exam_end: date | None = None
    reporting_time: str | None = None
    shift_details: str | None = None
    exam_city_slip_url: str | None = None
    # 4. Answer key & objections
    answer_key_release: date | None = None
    answer_key_url: str | None = None
    objection_deadline: date | None = None
    question_paper_url: str | None = None
    challenge_portal_url: str | None = None
    # 5. Result
    result_date: date | None = None
    merit_list_url: str | None = None
    scorecard_url: str | None = None
    cutoff_marks: dict[str, float] = Field(default_factory=dict)

    updated_at: datetime | None = None
