from __future__ import annotations

from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import CheckConstraint, Float, SmallInteger, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPkMixin, pg_enum
from app.domain.enums import Category
from app.domain.qualifications import QualificationLevel
from app.models.job import QUALIFICATION_LEVEL_ENUM

if TYPE_CHECKING:
    from app.models.application import UserApplication


class UserProfile(UUIDPkMixin, TimestampMixin, Base):
    __tablename__ = "user_profiles"
    __table_args__ = (
        CheckConstraint("ex_serviceman_service_years >= 0", name="exsm_years_non_negative"),
        CheckConstraint("experience_years >= 0", name="experience_non_negative"),
    )

    display_name: Mapped[str] = mapped_column(String(120))
    date_of_birth: Mapped[date]
    category: Mapped[Category] = mapped_column(pg_enum(Category, "category"))

    # --- Qualification (codes from app.domain.qualifications) ---------------
    qualification_tier: Mapped[QualificationLevel] = mapped_column(QUALIFICATION_LEVEL_ENUM)
    degree_title: Mapped[str] = mapped_column(String(20))  # "B_TECH", ..., or "OTHERS"
    custom_qualification_text: Mapped[str | None] = mapped_column(String(120))  # only for OTHERS
    experience_years: Mapped[float] = mapped_column(Float, default=0.0, server_default="0")

    is_pwbd: Mapped[bool] = mapped_column(default=False)
    is_ex_serviceman: Mapped[bool] = mapped_column(default=False)
    ex_serviceman_service_years: Mapped[int] = mapped_column(SmallInteger, default=0)
    fcm_token: Mapped[str | None] = mapped_column(String(512))

    applications: Mapped[list[UserApplication]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
