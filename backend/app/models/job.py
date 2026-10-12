from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Integer, SmallInteger, String, Text
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPkMixin
from app.domain.enums import Category


class JobPost(UUIDPkMixin, TimestampMixin, Base):
    """One recruitment notification / advertisement."""

    __tablename__ = "job_posts"

    organization: Mapped[str] = mapped_column(String(200))
    exam_name: Mapped[str] = mapped_column(String(300))
    advertisement_no: Mapped[str | None] = mapped_column(String(120))
    portal_url: Mapped[str | None] = mapped_column(String(1000))
    application_start: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    application_deadline: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    exam_date: Mapped[date | None]

    source_pdf_sha256: Mapped[str] = mapped_column(String(64), unique=True)
    source_pdf_path: Mapped[str | None] = mapped_column(String(500))
    extraction_model: Mapped[str] = mapped_column(String(80))
    # Set when the extractor's output failed a sanity check (e.g. seat sums mismatch).
    needs_review: Mapped[bool] = mapped_column(default=False)
    review_notes: Mapped[list[str]] = mapped_column(ARRAY(Text), default=list)

    posts: Mapped[list[PostDetail]] = relationship(
        back_populates="job_post",
        cascade="all, delete-orphan",
        order_by="PostDetail.post_code",
    )


class PostDetail(UUIDPkMixin, Base):
    """One post / post-code within a notification (e.g. 'Engineer (Electronics) – Post 03')."""

    __tablename__ = "post_details"

    job_post_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("job_posts.id", ondelete="CASCADE"), index=True)
    post_code: Mapped[str | None] = mapped_column(String(60))
    post_name: Mapped[str] = mapped_column(String(300))
    min_age: Mapped[int | None] = mapped_column(SmallInteger)
    base_max_age: Mapped[int | None] = mapped_column(SmallInteger)  # UR upper limit
    age_as_on: Mapped[date | None]  # the notification's age cut-off date
    eligible_streams: Mapped[list[str]] = mapped_column(ARRAY(String(200)), default=list)
    qualification_text: Mapped[str | None] = mapped_column(Text)
    # Notification-specific relaxations that override defaults: {"OBC": 3, "PWBD": 10, ...}
    age_relaxation_overrides: Mapped[dict[str, int]] = mapped_column(JSONB, default=dict)

    job_post: Mapped[JobPost] = relationship(back_populates="posts")
    vacancy: Mapped[VacancyMatrix | None] = relationship(
        back_populates="post", cascade="all, delete-orphan", uselist=False
    )


class VacancyMatrix(UUIDPkMixin, Base):
    __tablename__ = "vacancy_matrices"
    __table_args__ = (
        CheckConstraint(
            "ur >= 0 AND sc >= 0 AND st >= 0 AND obc >= 0 AND ews >= 0 AND total >= 0",
            name="non_negative_seats",
        ),
    )

    post_detail_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("post_details.id", ondelete="CASCADE"), unique=True
    )
    ur: Mapped[int] = mapped_column(Integer, default=0)
    sc: Mapped[int] = mapped_column(Integer, default=0)
    st: Mapped[int] = mapped_column(Integer, default=0)
    obc: Mapped[int] = mapped_column(Integer, default=0)
    ews: Mapped[int] = mapped_column(Integer, default=0)
    total: Mapped[int] = mapped_column(Integer, default=0)
    # Horizontal reservations (carved out of the vertical pools above); informational.
    pwbd: Mapped[int | None] = mapped_column(Integer)
    ex_serviceman: Mapped[int | None] = mapped_column(Integer)

    post: Mapped[PostDetail] = relationship(back_populates="vacancy")

    def seats_for(self, category: Category) -> int:
        return int(getattr(self, category.value.lower()))
