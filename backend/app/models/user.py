from __future__ import annotations

from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, SmallInteger, String
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPkMixin, pg_enum
from app.domain.enums import Category

if TYPE_CHECKING:
    from app.models.application import UserApplication


class UserProfile(UUIDPkMixin, TimestampMixin, Base):
    __tablename__ = "user_profiles"
    __table_args__ = (CheckConstraint("ex_serviceman_service_years >= 0", name="exsm_years_non_negative"),)

    display_name: Mapped[str] = mapped_column(String(120))
    date_of_birth: Mapped[date]
    category: Mapped[Category] = mapped_column(pg_enum(Category, "category"))
    # Free-text as the user types it ("B.Tech ECE"); canonicalised at match time.
    streams: Mapped[list[str]] = mapped_column(ARRAY(String(160)), default=list)
    is_pwbd: Mapped[bool] = mapped_column(default=False)
    is_ex_serviceman: Mapped[bool] = mapped_column(default=False)
    ex_serviceman_service_years: Mapped[int] = mapped_column(SmallInteger, default=0)
    fcm_token: Mapped[str | None] = mapped_column(String(512))

    applications: Mapped[list[UserApplication]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
