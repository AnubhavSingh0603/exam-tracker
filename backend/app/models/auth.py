from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPkMixin

if TYPE_CHECKING:
    from app.models.user import UserProfile


class User(UUIDPkMixin, TimestampMixin, Base):
    """A Google identity. Eligibility data lives in the linked UserProfile, which
    is created later (first-login users have no DOB/category yet)."""

    __tablename__ = "users"

    google_sub: Mapped[str] = mapped_column(String(64), unique=True)
    email: Mapped[str] = mapped_column(String(320), index=True)
    email_verified: Mapped[bool] = mapped_column(default=False)
    name: Mapped[str | None] = mapped_column(String(200))
    picture_url: Mapped[str | None] = mapped_column(String(1000))
    last_login_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    is_active: Mapped[bool] = mapped_column(default=True)
    # Lives here (not on user_profiles) so Phase 1 tables stay untouched.
    profile_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("user_profiles.id", ondelete="SET NULL"), unique=True
    )

    profile: Mapped[UserProfile | None] = relationship(lazy="joined")


class RefreshToken(TimestampMixin, Base):
    """Server-side record of every refresh token, for rotation and reuse detection.

    Each refresh rotates the token. Presenting an already-rotated token means it
    leaked, so the whole family (one login session) is revoked.
    """

    __tablename__ = "refresh_tokens"

    jti: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    family_id: Mapped[str] = mapped_column(String(64), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    replaced_by: Mapped[str | None] = mapped_column(String(64))
    user_agent: Mapped[str | None] = mapped_column(String(300))
