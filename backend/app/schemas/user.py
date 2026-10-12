import uuid
from datetime import date
from typing import Self

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.domain.enums import Category


class UserProfileCreate(BaseModel):
    display_name: str = Field(min_length=1, max_length=120)
    date_of_birth: date
    category: Category
    streams: list[str] = Field(default_factory=list, max_length=10, examples=[["B.Tech ECE"]])
    is_pwbd: bool = False
    is_ex_serviceman: bool = False
    ex_serviceman_service_years: int = Field(0, ge=0, le=40)

    @model_validator(mode="after")
    def _check(self) -> Self:
        if self.date_of_birth >= date.today():
            raise ValueError("date_of_birth must be in the past")
        if self.ex_serviceman_service_years and not self.is_ex_serviceman:
            raise ValueError("ex_serviceman_service_years requires is_ex_serviceman=true")
        return self


class UserProfileOut(UserProfileCreate):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
