"""Eligibility & reachable-seat calculator.

Pure: no I/O, no DB session, no clock. Accepts anything shaped like the ORM
models (see the Protocols below), so unit tests can pass plain dataclasses.
Evaluated per post (PostDetail): posts in one notification differ in age
limits, degrees and seats.

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

Qualification (broad degree-level model; tag in brackets)
  * A post needing a higher tier than the profile's is never shown.
  * "Any Post-Graduate" posts match every PG/PhD profile [Universal Post-Graduate].
  * "Any Graduate" posts match every UG/PG/PhD profile [Universal Graduate].
  * The profile's degree (or one it implies: M.Tech -> B.Tech) is in the
    post's allowed degrees [Direct Degree Match].
  * Plain 10th-pass posts match anyone above 10th; plain 12th-pass posts match
    UG and above [School Level].
  * OTHERS: the profile's free text is searched for in the eligibility text
    [Custom Qualification Match].
  * Nothing machine-readable in the post: shown, with "verify" note.

Experience
  * ``experience_years >= min_experience_years`` is a direct match; up to one
    year short => "Suggested: Experience Gap"; more => not shown.

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
from dataclasses import dataclass
from datetime import date
from typing import Protocol

from dateutil.relativedelta import relativedelta
from pydantic import BaseModel, ConfigDict

from app.domain.enums import (
    RELAXATION_KEY_EXSM,
    RELAXATION_KEY_PWBD,
    Category,
    MatchKind,
    MatchReason,
    SuggestionReason,
)
from app.domain.qualifications import LEVEL_LABELS, OTHERS, QualificationLevel, degree_codes_held
from app.services.streams import custom_text_matches, infer_requirement

DEFAULT_CATEGORY_RELAXATION: Mapping[Category, int] = {
    Category.UR: 0,
    Category.EWS: 0,
    Category.OBC: 3,
    Category.SC: 5,
    Category.ST: 5,
}
DEFAULT_PWBD_RELAXATION = 10
DEFAULT_EXSM_RELAXATION = 3  # added on top of years of military service rendered
MAX_SUGGESTED_EXPERIENCE_GAP = 1.0  # years

_L = QualificationLevel
_SCHOOL_DEGREES = frozenset({"CLASS_10", "CLASS_12"})

MATCH_REASON_LABELS: Mapping[MatchReason, str] = {
    MatchReason.DIRECT_DEGREE: "Direct Degree Match",
    MatchReason.UNIVERSAL_GRADUATE: "Universal Graduate Post",
    MatchReason.UNIVERSAL_POST_GRADUATE: "Universal Post-Graduate Post",
    MatchReason.SCHOOL_LEVEL: "School-Level Post",
    MatchReason.CUSTOM_QUALIFICATION: "Custom Qualification Match",
}


# --- Structural input types ------------------------------------------------


class ProfileLike(Protocol):
    date_of_birth: date
    category: Category
    qualification_tier: QualificationLevel
    degree_title: str
    custom_qualification_text: str | None
    experience_years: float
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
    qualification_text: str | None
    raw_eligibility_text: str | None
    allowed_degrees: Sequence[str]
    min_qualification_level: QualificationLevel | None
    is_open_to_any_graduate: bool
    is_open_to_any_post_graduate: bool
    min_experience_years: float
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

    is_eligible: bool  # every rule met (== direct match)
    eligible_via_relaxation: bool
    category_quota_seats: int
    ur_open_seats: int
    total_reachable_seats: int  # also filled for suggested posts

    age_on_cutoff: AgeOnCutoff | None
    effective_max_age: int | None
    relaxation_years: int
    qualification_match: bool | None  # None = could not verify
    match_reason: MatchReason | None  # which qualification rule matched
    reasons: tuple[str, ...]  # human-readable, shown in the detail view

    match_kind: MatchKind | None  # None = not shown at all
    suggestion_reasons: tuple[SuggestionReason, ...] = ()
    experience_gap_years: float = 0.0

    @property
    def is_direct_match(self) -> bool:
        return self.match_kind is MatchKind.DIRECT

    @property
    def is_suggested(self) -> bool:
        return self.match_kind is MatchKind.SUGGESTED

    @property
    def match_reason_label(self) -> str | None:
        return MATCH_REASON_LABELS[self.match_reason] if self.match_reason else None


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


def _level(value: object) -> QualificationLevel | None:
    if value is None or value == "":
        return None
    return value if isinstance(value, QualificationLevel) else QualificationLevel(str(value))


@dataclass(frozen=True, slots=True)
class QualificationOutcome:
    match: bool | None  # None = nothing machine-readable to check against
    reason: MatchReason | None
    note: str = ""


def evaluate_qualification(profile: ProfileLike, post: PostLike) -> QualificationOutcome:
    tier = _level(profile.qualification_tier)
    assert tier is not None
    lines = list(post.eligible_streams or ())
    req = infer_requirement(lines)
    allowed = set(post.allowed_degrees or ()) | set(req.allowed_degrees)
    any_grad = bool(post.is_open_to_any_graduate) or req.open_to_any_graduate
    any_pg = bool(post.is_open_to_any_post_graduate) or req.open_to_any_post_graduate

    levels = [lv for lv in (_level(post.min_qualification_level), req.min_level) if lv]
    levels += [_L.UG] if any_grad else []
    levels += [_L.PG] if any_pg else []
    need = min(levels, key=lambda lv: lv.rank) if levels else None

    if need is not None and tier.rank < need.rank:
        return QualificationOutcome(
            False, None, f"Needs {LEVEL_LABELS[need]}; your highest is {LEVEL_LABELS[tier]}."
        )
    if any_pg and tier.rank >= _L.PG.rank:
        return QualificationOutcome(True, MatchReason.UNIVERSAL_POST_GRADUATE)
    if any_grad and tier.rank >= _L.UG.rank:
        return QualificationOutcome(True, MatchReason.UNIVERSAL_GRADUATE)
    if degree_codes_held(profile.degree_title) & allowed:
        return QualificationOutcome(True, MatchReason.DIRECT_DEGREE)
    # Only *plain* 10th/12th posts cascade ("10th + ITI" lists ITI, so it doesn't).
    if allowed and allowed <= _SCHOOL_DEGREES:
        if (need is _L.MATRIC and tier.rank > _L.MATRIC.rank) or (
            need is _L.INTERMEDIATE and tier.rank >= _L.UG.rank
        ):
            return QualificationOutcome(True, MatchReason.SCHOOL_LEVEL)
    if profile.degree_title == OTHERS and profile.custom_qualification_text:
        haystacks = [post.raw_eligibility_text or "", post.qualification_text or "", *lines]
        if custom_text_matches(profile.custom_qualification_text, haystacks):
            return QualificationOutcome(True, MatchReason.CUSTOM_QUALIFICATION)
        if any(h.strip() for h in haystacks):
            return QualificationOutcome(False, None, "Your qualification isn't mentioned in the eligibility.")
    if not allowed and not any_grad and not any_pg and need is None:
        return QualificationOutcome(
            None, None, "Qualification could not be auto-verified — check the notification."
        )
    if not allowed and not any_grad and not any_pg:
        return QualificationOutcome(
            None, None, f"Needs {LEVEL_LABELS[need]} (degree not specified) — check the notification."
        )
    return QualificationOutcome(False, None, "Your degree is not in the eligible list.")


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
    qual = evaluate_qualification(profile, post)
    if qual.note:
        reasons.append(qual.note)

    # 3. Experience ----------------------------------------------------------------
    need_exp = float(post.min_experience_years or 0)
    have_exp = float(profile.experience_years or 0)
    gap = round(max(0.0, need_exp - have_exp), 2)
    if gap > 0:
        reasons.append(f"Needs {need_exp:g} yr experience; you have {have_exp:g}.")

    # 4. Direct / suggested / hidden ------------------------------------------------
    hard_fail = not age_ok or qual.match is False or gap > MAX_SUGGESTED_EXPERIENCE_GAP
    if hard_fail:
        kind = None
    elif gap > 0:
        kind = MatchKind.SUGGESTED
    else:
        kind = MatchKind.DIRECT

    # 5. Seats ------------------------------------------------------------------
    quota = ur_open = 0
    vac = post.vacancy
    if vac is None:
        reasons.append("Vacancy break-up not available.")
    elif kind is not None:
        if profile.category is Category.UR:
            ur_open = vac.ur
        else:
            quota = int(getattr(vac, profile.category.value.lower()))
            if strict_ur_migration and via_relaxation:
                reasons.append("Age relaxation used: UR (open) seats not reachable.")
            else:
                ur_open = vac.ur

    return EligibilityResult(
        is_eligible=kind is MatchKind.DIRECT,
        eligible_via_relaxation=kind is not None and via_relaxation,
        category_quota_seats=quota,
        ur_open_seats=ur_open,
        total_reachable_seats=quota + ur_open,
        age_on_cutoff=age,
        effective_max_age=effective_max,
        relaxation_years=relax,
        qualification_match=qual.match,
        match_reason=qual.reason,
        reasons=tuple(reasons),
        match_kind=kind,
        suggestion_reasons=(SuggestionReason.EXPERIENCE_GAP,) if kind is MatchKind.SUGGESTED else (),
        experience_gap_years=gap,
    )
