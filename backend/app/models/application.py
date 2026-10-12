from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, LargeBinary, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.security import decrypt_secret, encrypt_secret
from app.db.base import Base, TimestampMixin, UUIDPkMixin, pg_enum
from app.domain.enums import ApplicationStatus

if TYPE_CHECKING:
    from app.models.job import PostDetail
    from app.models.user import UserProfile


class UserApplication(UUIDPkMixin, TimestampMixin, Base):
    __tablename__ = "user_applications"
    __table_args__ = (UniqueConstraint("user_id", "post_detail_id", name="user_post"),)

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True)
    post_detail_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("post_details.id", ondelete="CASCADE"), index=True
    )
    status: Mapped[ApplicationStatus] = mapped_column(
        pg_enum(ApplicationStatus, "application_status"), default=ApplicationStatus.DISCOVERED
    )

    # --- Credential Vault ---------------------------------------------------
    registration_id: Mapped[str | None] = mapped_column(String(120))
    roll_number: Mapped[str | None] = mapped_column(String(120))
    portal_username: Mapped[str | None] = mapped_column(String(200))
    portal_password_enc: Mapped[bytes | None] = mapped_column(LargeBinary)

    applied_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    exam_datetime: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    # --- Device calendar sync ----------------------------------------------
    calendar_event_synced: Mapped[bool] = mapped_column(default=False)
    calendar_event_id: Mapped[str | None] = mapped_column(String(120))

    user: Mapped[UserProfile] = relationship(back_populates="applications")
    post: Mapped[PostDetail] = relationship()

    @property
    def portal_password(self) -> str | None:
        return decrypt_secret(self.portal_password_enc) if self.portal_password_enc else None

    @portal_password.setter
    def portal_password(self, value: str | None) -> None:
        self.portal_password_enc = encrypt_secret(value) if value else None
