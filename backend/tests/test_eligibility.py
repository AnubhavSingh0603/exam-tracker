from dataclasses import dataclass, field
from datetime import date

import pytest

from app.domain.enums import Category, MatchKind, MatchReason, SuggestionReason
from app.domain.qualifications import QualificationLevel as L
from app.services.eligibility import age_on, evaluate_eligibility
from app.services.streams import custom_text_matches, infer_requirement


@dataclass
class Profile:
    date_of_birth: date
    category: Category
    qualification_tier: L = L.UG
    degree_title: str = "B_TECH"
    custom_qualification_text: str | None = None
    experience_years: float = 0.0
    is_pwbd: bool = False
    is_ex_serviceman: bool = False
    ex_serviceman_service_years: int = 0


@dataclass
class Vacancy:
    ur: int = 20
    sc: int = 6
    st: int = 3
    obc: int = 11
    ews: int = 4


@dataclass
class Post:
    base_max_age: int | None = 25
    min_age: int | None = 18
    age_as_on: date | None = date(2026, 10, 1)
    eligible_streams: list[str] = field(default_factory=lambda: ["B.E./B.Tech Electronics & Communication"])
    qualification_text: str | None = None
    raw_eligibility_text: str | None = None
    allowed_degrees: list[str] = field(default_factory=list)
    min_qualification_level: L | None = None
    is_open_to_any_graduate: bool = False
    is_open_to_any_post_graduate: bool = False
    min_experience_years: float = 0.0
    age_relaxation_overrides: dict[str, int] = field(default_factory=dict)
    vacancy: Vacancy | None = field(default_factory=Vacancy)


AGE_28 = date(1998, 6, 15)  # 28y on 2026-10-01
YOUNG = date(2002, 1, 1)


def ur(**kw) -> Profile:
    return Profile(YOUNG, Category.UR, **kw)


# --- Age & seats (unchanged rules) ----------------------------------------------


def test_age_uses_completed_years_on_cutoff():
    assert age_on(date(2000, 10, 2), date(2026, 10, 1)).years == 25
    assert age_on(date(2000, 10, 1), date(2026, 10, 1)).years == 26


def test_spec_example_sc_28_vs_ur_25_is_eligible_via_relaxation():
    r = evaluate_eligibility(Profile(AGE_28, Category.SC), Post())
    assert r.is_eligible and r.eligible_via_relaxation
    assert r.effective_max_age == 30
    assert r.category_quota_seats == 6
    # Relaxation used -> no migration to UR under the strict rule
    assert r.ur_open_seats == 0
    assert r.total_reachable_seats == 6


def test_sc_without_relaxation_reaches_ur_plus_quota():
    r = evaluate_eligibility(Profile(YOUNG, Category.SC), Post())
    assert r.is_eligible and not r.eligible_via_relaxation
    assert (r.category_quota_seats, r.ur_open_seats, r.total_reachable_seats) == (6, 20, 26)


def test_non_strict_mode_pools_ur_even_with_relaxation():
    r = evaluate_eligibility(Profile(AGE_28, Category.SC), Post(), strict_ur_migration=False)
    assert r.total_reachable_seats == 26


def test_ur_28_is_not_eligible():
    r = evaluate_eligibility(Profile(AGE_28, Category.UR), Post())
    assert not r.is_eligible and r.match_kind is None
    assert r.total_reachable_seats == 0


def test_obc_plus_pwbd_stacks():
    r = evaluate_eligibility(Profile(date(1988, 1, 1), Category.OBC, is_pwbd=True), Post())
    assert r.relaxation_years == 13 and r.effective_max_age == 38
    assert r.is_eligible


def test_ews_gets_no_relaxation():
    r = evaluate_eligibility(Profile(date(2000, 1, 1), Category.EWS), Post())  # 26
    assert not r.is_eligible


def test_ex_serviceman_adds_service_years():
    p = Profile(date(1994, 1, 1), Category.UR, is_ex_serviceman=True, ex_serviceman_service_years=6)
    r = evaluate_eligibility(p, Post())  # 32 <= 25 + 3 + 6
    assert r.is_eligible and r.effective_max_age == 34


def test_notification_override_wins():
    r = evaluate_eligibility(Profile(AGE_28, Category.OBC), Post(age_relaxation_overrides={"OBC": 5}))
    assert r.is_eligible and r.effective_max_age == 30


def test_missing_vacancy_matrix():
    r = evaluate_eligibility(Profile(YOUNG, Category.SC), Post(vacancy=None))
    assert r.is_eligible and r.total_reachable_seats == 0


# --- Degree matching --------------------------------------------------------------


def test_direct_degree_match_ignores_branch():
    # Branches are deliberately not compared: any B.Tech matches a B.Tech post.
    r = evaluate_eligibility(ur(degree_title="B_TECH"), Post(eligible_streams=["B.E./B.Tech Civil"]))
    assert r.is_eligible and r.match_reason is MatchReason.DIRECT_DEGREE
    assert r.match_reason_label == "Direct Degree Match"


def test_other_degree_does_not_match_degree_specific_post():
    r = evaluate_eligibility(ur(degree_title="B_SC"), Post())
    assert not r.is_eligible and r.qualification_match is False and r.match_kind is None


def test_pg_degree_implies_its_bachelors():
    r = evaluate_eligibility(ur(qualification_tier=L.PG, degree_title="M_TECH"), Post())
    assert r.is_eligible and r.match_reason is MatchReason.DIRECT_DEGREE


def test_explicit_allowed_degrees_are_used():
    post = Post(eligible_streams=[], allowed_degrees=["B_COM"], min_qualification_level=L.UG)
    assert evaluate_eligibility(ur(degree_title="B_COM"), post).is_eligible
    assert not evaluate_eligibility(ur(degree_title="B_A"), post).is_eligible


@pytest.mark.parametrize(
    ("tier", "degree", "ok"),
    [
        (L.UG, "B_A", True),
        (L.PG, "MBA", True),
        (L.PHD, "PHD", True),
        (L.UG, "OTHERS", True),
        (L.DIPLOMA, "DIPLOMA", False),
        (L.INTERMEDIATE, "CLASS_12", False),
    ],
)
def test_any_graduate_post_matches_every_graduate(tier, degree, ok):
    custom = "B.Des" if degree == "OTHERS" else None
    profile = ur(qualification_tier=tier, degree_title=degree, custom_qualification_text=custom)
    r = evaluate_eligibility(profile, Post(eligible_streams=["Graduation in any discipline"]))
    assert r.is_eligible is ok
    if ok:
        assert r.match_reason is MatchReason.UNIVERSAL_GRADUATE
        assert r.match_reason_label == "Universal Graduate Post"


def test_any_pg_post_needs_pg():
    post = Post(eligible_streams=[], is_open_to_any_post_graduate=True)
    assert not evaluate_eligibility(ur(), post).is_eligible
    r = evaluate_eligibility(ur(qualification_tier=L.PG, degree_title="M_A"), post)
    assert r.is_eligible and r.match_reason is MatchReason.UNIVERSAL_POST_GRADUATE


@pytest.mark.parametrize(
    ("tier", "degree", "school_post", "ok"),
    [
        (L.UG, "B_TECH", "12th pass", True),
        (L.PG, "MBA", "10th pass / Matriculation", True),
        (L.DIPLOMA, "ITI", "Matriculation", True),
        (L.DIPLOMA, "DIPLOMA", "12th pass", False),  # only UG+ cascades to 12th posts
        (L.MATRIC, "CLASS_10", "12th pass", False),
        (L.INTERMEDIATE, "CLASS_12", "12th pass", True),  # exact degree
    ],
)
def test_school_level_cascade(tier, degree, school_post, ok):
    r = evaluate_eligibility(
        ur(qualification_tier=tier, degree_title=degree), Post(eligible_streams=[school_post])
    )
    assert r.is_eligible is ok


def test_trade_posts_do_not_cascade():
    # "10th + ITI" needs the ITI; a graduate without it isn't auto-matched.
    r = evaluate_eligibility(
        ur(degree_title="B_A"), Post(eligible_streams=["10th pass with ITI (Electrician)"])
    )
    assert not r.is_eligible


def test_needs_higher_tier_explains_why():
    r = evaluate_eligibility(ur(), Post(eligible_streams=["M.Tech in any discipline"]))
    assert not r.is_eligible
    assert any("Needs Post-Graduation" in n for n in r.reasons)


def test_unknown_qualification_does_not_block():
    r = evaluate_eligibility(ur(), Post(eligible_streams=[]))
    assert r.is_eligible and r.qualification_match is None


# --- "Others" ---------------------------------------------------------------------------


def _others(text: str, tier: L = L.UG) -> Profile:
    return ur(qualification_tier=tier, degree_title="OTHERS", custom_qualification_text=text)


def test_others_found_in_eligibility_text():
    post = Post(
        eligible_streams=["B.Des / Bachelor of Design"],
        raw_eligibility_text="Bachelor's Degree in Design (B.Des) from a recognised institute.",
    )
    r = evaluate_eligibility(_others("B.Des"), post)
    assert r.is_eligible and r.match_reason is MatchReason.CUSTOM_QUALIFICATION
    assert r.match_reason_label == "Custom Qualification Match"


def test_others_not_found_is_not_eligible():
    post = Post(eligible_streams=["BAMS"], raw_eligibility_text="BAMS degree from a recognised university")
    assert not evaluate_eligibility(_others("BVSc"), post).is_eligible
    assert evaluate_eligibility(_others("BAMS"), post).is_eligible


@pytest.mark.parametrize(
    ("custom", "text", "ok"),
    [
        ("CA/CS", "Qualified CA or ICWA", True),
        ("B Des (Fashion)", "B.Des from NIFT", True),
        ("Bachelor of Design", "Bachelor of Design (B.Des)", True),
        ("BVSc", "B.V.Sc & A.H.", True),
        ("CA", "Graduate with knowledge of Excel", False),
        ("Bachelor", "Bachelor's degree in Engineering", False),  # too generic on its own
    ],
)
def test_custom_text_search(custom, text, ok):
    assert custom_text_matches(custom, [text]) is ok


# --- Experience & feed split ---------------------------------------------------------


def test_experience_met_is_direct():
    r = evaluate_eligibility(ur(experience_years=2), Post(min_experience_years=2))
    assert r.match_kind is MatchKind.DIRECT


def test_up_to_one_year_short_is_suggested_with_seats():
    r = evaluate_eligibility(ur(experience_years=1.5), Post(min_experience_years=2))
    assert r.match_kind is MatchKind.SUGGESTED and not r.is_eligible
    assert r.suggestion_reasons == (SuggestionReason.EXPERIENCE_GAP,)
    assert r.experience_gap_years == 0.5
    assert r.total_reachable_seats == 20


def test_fresher_more_than_a_year_short_is_hidden():
    r = evaluate_eligibility(ur(), Post(min_experience_years=3))
    assert r.match_kind is None


# --- Notification-line parsing ---------------------------------------------------------


@pytest.mark.parametrize(
    ("lines", "degrees", "level", "any_grad", "any_pg"),
    [
        (["B.E./B.Tech Electronics & Communication"], ("B_TECH",), L.UG, False, False),
        (["Graduation from a recognised university"], (), L.UG, True, False),
        (["Post Graduate degree in any discipline"], (), L.PG, False, True),
        (["MBBS", "MD/MS (Anaesthesia)"], ("MBBS", "MD_MS"), L.UG, False, False),
        (["Diploma in Civil Engg.", "B.E. Civil"], ("DIPLOMA", "B_TECH"), L.DIPLOMA, False, False),
        (["B.Ed with B.A."], ("B_ED",), L.UG, False, False),
        (["Graduate with knowledge of computer applications"], (), L.UG, True, False),
    ],
)
def test_infer_requirement(lines, degrees, level, any_grad, any_pg):
    req = infer_requirement(lines)
    assert req.allowed_degrees == degrees
    assert req.min_level is level
    assert (req.open_to_any_graduate, req.open_to_any_post_graduate) == (any_grad, any_pg)
