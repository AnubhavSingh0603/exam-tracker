"""Eligibility & reachable-seat calculator.

Pure: no I/O, no DB session, no clock. Accepts anything shaped like the ORM
models (see the Protocols below), so unit tests can pass plain dataclasses.

Rules implemented
-----------------
Age
  * Age is computed in completed years on the post's ``age_as_on`` date
    (``relativedelta``), so a candidate who is 25y 11m is "25" — the standard
    reading of "should not exceed 25 years".
  * Effective Max Age = base (UR) max + category relaxation
                        + PwBD relaxation (if applicable)
                        + Ex-Serviceman relaxation (if applicable).
  * Defaults (Central Govt): SC/ST +5, OBC(NCL) +3, EWS/UR 0, PwBD +10,
    ESM = +3 plus years of military service. Any of these can be overridden
    per post via ``age_relaxation_overrides`` (PSUs often differ).

Seats
  * A reserved-category candidate contests their own quota AND the open (UR)
    pool: total = UR + own-category seats.
  * Exception (``strict_ur_migration``): a reserved candidate who is only
    eligible *because of* an age relaxation cannot be adjusted against UR seats,
    so ``ur_open_seats`` becomes 0.
  * A UR candidate only has the UR pool; ``category_quota_seats`` is 0.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from datetime import date
from typing import Protocol

from dateutil.relativedelta import relativedelta
from pydantic import BaseModel, ConfigDict

from app.domain.enums import RELAXATION_KEY_EXSM, RELAXATION_KEY_PWBD, Category
from app.services.streams import match_streams

DEFAULT_CATEGORY_RELAXATION: Mapping[Category, int] = {
    Category.UR: 0,
    Category.EWS: 0,
    Category.OBC: 3,
    Category.SC: 5,
    Category.ST: 5,
}
DEFAULT_PWBD_RELAXATION = 10
DEFAULT_EXSM_RELAXATION = 3  # added on top of years of military service rendered


# --- Structural input types ------------------------------------------------


class ProfileLike(Protocol):
    date_of_birth: date
    category: Category
    streams: Sequence[str]
    is_pwbd: bool
    is_ex_serviceman: bool
    ex_serviceman_service_years: int


class VacancyLike(Protocol):
    ur: int
    sc: int
    st: int
    obc: int
    ews: int


class PostLike(Protocol):
    min_age: int | None
    base_max_age: int | None
    age_as_on: date | None
    eligible_streams: Sequence[str]
    age_relaxation_overrides: Mapping[str, int] | None
    vacancy: VacancyLike | None


# --- Output -----------------------------------------------------------------


class AgeOnCutoff(BaseModel):
    model_config = ConfigDict(frozen=True)
    years: int
    months: int
    days: int


class EligibilityResult(BaseModel):
    model_config = ConfigDict(frozen=True)

    is_eligible: bool
    eligible_via_relaxation: bool
    category_quota_seats: int
    ur_open_seats: int
    total_reachable_seats: int

    age_on_cutoff: AgeOnCutoff | None
    effective_max_age: int | None
    relaxation_years: int
    qualification_match: bool | None  # None = could not verify
    reasons: tuple[str, ...]  # human-readable, shown in the detail view


# --- Helpers -----------------------------------------------------------------


def age_on(dob: date, as_on: date) -> AgeOnCutoff:
    if dob > as_on:
        raise ValueError(f"date_of_birth {dob} is after cut-off {as_on}")
    rd = relativedelta(as_on, dob)
    return AgeOnCutoff(years=rd.years, months=rd.months, days=rd.days)


def total_relaxation_years(profile: ProfileLike, overrides: Mapping[str, int] | None = None) -> int:
    o = overrides or {}
    years = o.get(profile.category.value, DEFAULT_CATEGORY_RELAXATION[profile.category])
    if profile.category is Category.UR:
        years = 0  # never let a stray override relax the open category
    if profile.is_pwbd:
        years += o.get(RELAXATION_KEY_PWBD, DEFAULT_PWBD_RELAXATION)
    if profile.is_ex_serviceman:
        years += o.get(RELAXATION_KEY_EXSM, DEFAULT_EXSM_RELAXATION)
        years += max(0, profile.ex_serviceman_service_years)
    return max(0, years)


# --- Main entry point ---------------------------------------------------------


def evaluate_eligibility(
    profile: ProfileLike,
    post: PostLike,
    *,
    strict_ur_migration: bool = True,
) -> EligibilityResult:
    reasons: list[str] = []
    age_ok = True
    via_relaxation = False
    effective_max: int | None = None
    age: AgeOnCutoff | None = None
    relax = total_relaxation_years(profile, post.age_relaxation_overrides)

    # 1. Age ------------------------------------------------------------------
    if post.age_as_on is None:
        reasons.append("Age cut-off date not found in notification — age not verified.")
    else:
        age = age_on(profile.date_of_birth, post.age_as_on)
        if post.min_age is not None and age.years < post.min_age:
            age_ok = False
            reasons.append(f"Below minimum age {post.min_age} on {post.age_as_on:%d %b %Y}.")
        if post.base_max_age is not None:
            effective_max = post.base_max_age + relax
            if age.years > effective_max:
                age_ok = False
                reasons.append(
                    f"Age {age.years} exceeds limit {effective_max} "
                    f"(base {post.base_max_age} + {relax} relaxation)."
                )
            elif age.years > post.base_max_age:
                via_relaxation = True
                reasons.append(
                    f"Eligible via {relax}-year relaxation (age {age.years}, limit {effective_max})."
                )

    # 2. Qualification -----------------------------------------------------------
    qual = match_streams(profile.streams, post.eligible_streams)
    if qual is False:
        reasons.append("Your degree/branch is not in the eligible list.")
    elif qual is None:
        reasons.append("Qualification could not be auto-verified — check the notification.")

    is_eligible = age_ok and qual is not False

    # 3. Seats ------------------------------------------------------------------
    quota = ur_open = 0
    vac = post.vacancy
    if vac is None:
        reasons.append("Vacancy break-up not available.")
    elif is_eligible:
        if profile.category is Category.UR:
            ur_open = vac.ur
        else:
            quota = int(getattr(vac, profile.category.value.lower()))
            if strict_ur_migration and via_relaxation:
                reasons.append("Age relaxation used: UR (open) seats not reachable.")
            else:
                ur_open = vac.ur

    return EligibilityResult(
        is_eligible=is_eligible,
        eligible_via_relaxation=is_eligible and via_relaxation,
        category_quota_seats=quota,
        ur_open_seats=ur_open,
        total_reachable_seats=quota + ur_open,
        age_on_cutoff=age,
        effective_max_age=effective_max,
        relaxation_years=relax,
        qualification_match=qual,
        reasons=tuple(reasons),
    )
