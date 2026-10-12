from __future__ import annotations

import uuid
from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPkMixin

if TYPE_CHECKING:
    from app.models.job import JobPost


class ExamLifecycleTimeline(UUIDPkMixin, TimestampMixin, Base):
    """Post-application milestones of one notification, shared by every applicant.

    Filled from the notification PDF (tentative dates) and later from scraped
    alerts (admit card / answer key / result links). Each user's *progress* is
    derived on the phone from these dates plus their own "Applied" mark.
    Stage 1 (application window start/end) lives on JobPost itself.
    """

    __tablename__ = "exam_lifecycle_timelines"

    job_post_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("job_posts.id", ondelete="CASCADE"), unique=True
    )

    # 1. Application window (start/end: JobPost.application_start/_deadline)
    fee_deadline: Mapped[date | None]
    edit_window_start: Mapped[date | None]
    edit_window_end: Mapped[date | None]

    # 2. Admit card / hall ticket
    admit_card_release: Mapped[date | None]
    admit_card_url: Mapped[str | None] = mapped_column(String(1000))

    # 3. Examination
    exam_start: Mapped[date | None]
    exam_end: Mapped[date | None]  # multi-day CBT windows
    reporting_time: Mapped[str | None] = mapped_column(String(60))
    shift_details: Mapped[str | None] = mapped_column(String(300))
    exam_city_slip_url: Mapped[str | None] = mapped_column(String(1000))

    # 4. Answer key & objections
    answer_key_release: Mapped[date | None]
    answer_key_url: Mapped[str | None] = mapped_column(String(1000))
    objection_deadline: Mapped[date | None]
    question_paper_url: Mapped[str | None] = mapped_column(String(1000))
    challenge_portal_url: Mapped[str | None] = mapped_column(String(1000))

    # 5. Results & cut-offs
    result_date: Mapped[date | None]
    merit_list_url: Mapped[str | None] = mapped_column(String(1000))
    scorecard_url: Mapped[str | None] = mapped_column(String(1000))
    cutoff_marks: Mapped[dict[str, float]] = mapped_column(JSONB, default=dict)  # {"UR": 142.5, "SC": 118}

    job_post: Mapped[JobPost] = relationship(back_populates="timeline")
