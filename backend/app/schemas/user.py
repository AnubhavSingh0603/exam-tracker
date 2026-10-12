import uuid
from datetime import date
from typing import Self

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.domain.enums import Category
from app.domain.qualifications import DEGREES_BY_CODE, OTHERS, QualificationLevel


class UserProfileCreate(BaseModel):
    display_name: str = Field(min_length=1, max_length=120)
    date_of_birth: date
    category: Category

    # Codes from GET /api/v1/meta/qualifications.
    qualification_tier: QualificationLevel
    degree_title: str = Field(max_length=20, examples=["B_TECH", "OTHERS"])
    custom_qualification_text: str | None = Field(
        None, max_length=120, examples=["B.Des"], description="Required when degree_title is OTHERS"
    )
    experience_years: float = Field(0.0, ge=0, le=50)

    is_pwbd: bool = False
    is_ex_serviceman: bool = False
    ex_serviceman_service_years: int = Field(0, ge=0, le=40)

    @model_validator(mode="after")
    def _check(self) -> Self:
        if self.date_of_birth >= date.today():
            raise ValueError("date_of_birth must be in the past")
        if self.ex_serviceman_service_years and not self.is_ex_serviceman:
            raise ValueError("ex_serviceman_service_years requires is_ex_serviceman=true")

        if self.degree_title == OTHERS:
            text = (self.custom_qualification_text or "").strip()
            if len(text) < 2:
                raise ValueError("custom_qualification_text is required when degree_title is OTHERS")
            self.custom_qualification_text = text
            return self
        degree = DEGREES_BY_CODE.get(self.degree_title)
        if degree is None:
            raise ValueError(f"Unknown degree_title {self.degree_title!r}")
        if degree.level is not self.qualification_tier:
            raise ValueError(
                f"{degree.code} is a {degree.level.value} qualification, not {self.qualification_tier}"
            )
        self.custom_qualification_text = None
        return self


class UserProfileOut(UserProfileCreate):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
