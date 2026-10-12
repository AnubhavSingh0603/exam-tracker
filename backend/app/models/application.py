from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, LargeBinary, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.security import decrypt_secret, encrypt_secret
from app.db.base import Base, TimestampMixin, UUIDPkMixin, pg_enum
from app.domain.enums import ApplicationStatus, ExamMilestone, UpdateSource

if TYPE_CHECKING:
    from app.models.job import JobPost, PostDetail
    from app.models.user import UserProfile


class UserApplication(UUIDPkMixin, TimestampMixin, Base):
    """An exam the user applied to: the unit the exam watcher tracks.

    Created from the feed ("Applied" on a post) or manually by name + portal link.
    From here on the candidate's qualifications play no part: the watcher only
    follows this exam's notices.
    """

    __tablename__ = "user_applications"
    __table_args__ = (UniqueConstraint("user_id", "post_detail_id", name="user_post"),)

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True)
    # Both NULL for exams added by hand (not in our notification database).
    post_detail_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("post_details.id", ondelete="SET NULL"), index=True
    )
    job_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("job_posts.id", ondelete="SET NULL"), index=True
    )
    exam_name: Mapped[str] = mapped_column(String(300))
    organization: Mapped[str | None] = mapped_column(String(200))
    official_portal_url: Mapped[str | None] = mapped_column(String(1000))
    status: Mapped[ApplicationStatus] = mapped_column(
        pg_enum(ApplicationStatus, "application_status"), default=ApplicationStatus.APPLIED
    )

    # --- Credential Vault ---------------------------------------------------
    registration_id: Mapped[str | None] = mapped_column(String(120))
    roll_number: Mapped[str | None] = mapped_column(String(120))
    portal_username: Mapped[str | None] = mapped_column(String(200))
    portal_password_enc: Mapped[bytes | None] = mapped_column(LargeBinary)

    applied_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    exam_datetime: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # --- Exam watcher -------------------------------------------------------
    last_checked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_check_error: Mapped[str | None] = mapped_column(Text)

    # --- Device calendar sync ----------------------------------------------
    calendar_event_synced: Mapped[bool] = mapped_column(default=False)
    calendar_event_id: Mapped[str | None] = mapped_column(String(120))

    user: Mapped[UserProfile] = relationship(back_populates="applications")
    post: Mapped[PostDetail | None] = relationship()
    job: Mapped[JobPost | None] = relationship()
    updates: Mapped[list[ExamUpdateLog]] = relationship(
        back_populates="application",
        cascade="all, delete-orphan",
        order_by="ExamUpdateLog.detected_at.desc()",
    )

    @property
    def is_watched(self) -> bool:
        return self.status not in (ApplicationStatus.DISCOVERED, ApplicationStatus.RESULT_DECLARED)

    @property
    def portal_password(self) -> str | None:
        return decrypt_secret(self.portal_password_enc) if self.portal_password_enc else None

    @portal_password.setter
    def portal_password(self, value: str | None) -> None:
        self.portal_password_enc = encrypt_secret(value) if value else None


class ExamUpdateLog(UUIDPkMixin, Base):
    """One notice the exam watcher found for one application, and whether the
    user has been pinged about it. A notice URL is recorded once per application,
    which is what makes the watcher's diff cheap: only unseen URLs are new."""

    __tablename__ = "exam_update_log"
    __table_args__ = (UniqueConstraint("application_id", "url", name="application_url"),)

    application_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("user_applications.id", ondelete="CASCADE"), index=True
    )
    milestone: Mapped[ExamMilestone] = mapped_column(pg_enum(ExamMilestone, "exam_milestone"))
    source: Mapped[UpdateSource] = mapped_column(pg_enum(UpdateSource, "update_source"))
    title: Mapped[str] = mapped_column(String(500))
    url: Mapped[str] = mapped_column(String(2000))  # the notice PDF or login/download page
    event_date: Mapped[date | None]  # e.g. the exam date printed next to the notice
    detected_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    # Delivery state: NULL notified_at = still to push (held in quiet hours, or no device yet).
    notified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    notify_error: Mapped[str | None] = mapped_column(String(300))

    application: Mapped[UserApplication] = relationship(back_populates="updates")
