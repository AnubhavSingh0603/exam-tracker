from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPkMixin


class DeviceToken(UUIDPkMixin, TimestampMixin, Base):
    """One FCM registration token per installed app instance."""

    __tablename__ = "device_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token: Mapped[str] = mapped_column(String(512), unique=True)
    # "token" = FCM registration token, "fid" = Firebase Installation ID (firebase-admin 7+)
    kind: Mapped[str] = mapped_column(String(10), default="token")
    platform: Mapped[str] = mapped_column(String(20), default="android")
    app_version_code: Mapped[int | None] = mapped_column(Integer)
    last_success_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failures: Mapped[int] = mapped_column(Integer, default=0)


class NotificationLog(UUIDPkMixin, Base):
    """De-duplication: each (user, kind, ref) is pushed at most once."""

    __tablename__ = "notification_log"
    __table_args__ = (UniqueConstraint("user_id", "kind", "ref", name="notification_once"),)

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    kind: Mapped[str] = mapped_column(String(40))  # deadline_72h | admit_card
    ref: Mapped[str] = mapped_column(String(64))  # job_post_id or discovered_item id
    sent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
