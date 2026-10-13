"""Shared helpers for the Python <-> Dart eligibility parity cases."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Any

from app.domain.enums import Category
from app.domain.qualifications import QualificationLevel
from app.services.eligibility import evaluate_eligibility


@dataclass
class _Vacancy:
    ur: int
    sc: int
    st: int
    obc: int
    ews: int
    total: int = 0


@dataclass
class _Profile:
    date_of_birth: date
    category: Category
    qualification_tier: QualificationLevel
    degree_title: str
    custom_qualification_text: str | None
    experience_years: float
    is_pwbd: bool
    is_ex_serviceman: bool
    ex_serviceman_service_years: int


@dataclass
class _Post:
    min_age: int | None
    base_max_age: int | None
    age_as_on: date | None
    eligible_streams: list[str]
    qualification_text: str | None
    raw_eligibility_text: str | None
    allowed_degrees: list[str]
    min_qualification_level: QualificationLevel | None
    is_open_to_any_graduate: bool
    is_open_to_any_post_graduate: bool
    min_experience_years: float
    age_relaxation_overrides: dict[str, int] = field(default_factory=dict)
    vacancy: _Vacancy | None = None


def _date(v: str | None) -> date | None:
    return date.fromisoformat(v) if v else None


def evaluate_case(profile: dict[str, Any], post: dict[str, Any]) -> dict[str, Any]:
    p = _Profile(
        date_of_birth=date.fromisoformat(profile["date_of_birth"]),
        category=Category(profile["category"]),
        qualification_tier=QualificationLevel(profile["qualification_tier"]),
        degree_title=profile["degree_title"],
        custom_qualification_text=profile["custom_qualification_text"],
        experience_years=profile["experience_years"],
        is_pwbd=profile["is_pwbd"],
        is_ex_serviceman=profile["is_ex_serviceman"],
        ex_serviceman_service_years=profile["ex_serviceman_service_years"],
    )
    level = post["min_qualification_level"]
    q = _Post(
        min_age=post["min_age"],
        base_max_age=post["base_max_age"],
        age_as_on=_date(post["age_as_on"]),
        # Published posts already contain what these lines imply (publish.merged_requirement),
        # so Python re-reading them changes nothing; the phone uses them only as search text.
        eligible_streams=post["eligible_streams"],
        qualification_text=post["qualification_text"],
        raw_eligibility_text=post["raw_eligibility_text"],
        allowed_degrees=post["allowed_degrees"],
        min_qualification_level=QualificationLevel(level) if level else None,
        is_open_to_any_graduate=post["is_open_to_any_graduate"],
        is_open_to_any_post_graduate=post["is_open_to_any_post_graduate"],
        min_experience_years=post["min_experience_years"],
        age_relaxation_overrides=post["age_relaxation_overrides"],
        vacancy=_Vacancy(**post["vacancy"]) if post["vacancy"] else None,
    )
    r = evaluate_eligibility(p, q)
    return {
        "match_kind": r.match_kind.value if r.match_kind else None,
        "is_eligible": r.is_eligible,
        "qualification_match": r.qualification_match,
        "match_reason": r.match_reason.value if r.match_reason else None,
        "eligible_via_relaxation": r.eligible_via_relaxation,
        "effective_max_age": r.effective_max_age,
        "relaxation_years": r.relaxation_years,
        "category_quota_seats": r.category_quota_seats,
        "ur_open_seats": r.ur_open_seats,
        "total_reachable_seats": r.total_reachable_seats,
        "experience_gap_years": r.experience_gap_years,
    }
