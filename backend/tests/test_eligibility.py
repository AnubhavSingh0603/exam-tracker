from dataclasses import dataclass, field
from datetime import date

import pytest

from app.domain.enums import Category
from app.services.eligibility import age_on, evaluate_eligibility


@dataclass
class Profile:
    date_of_birth: date
    category: Category
    streams: list[str] = field(default_factory=lambda: ["B.Tech ECE"])
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
    age_relaxation_overrides: dict[str, int] = field(default_factory=dict)
    vacancy: Vacancy | None = field(default_factory=Vacancy)


AGE_28 = date(1998, 6, 15)  # 28y on 2026-10-01


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
    r = evaluate_eligibility(Profile(date(2002, 1, 1), Category.SC), Post())
    assert r.is_eligible and not r.eligible_via_relaxation
    assert (r.category_quota_seats, r.ur_open_seats, r.total_reachable_seats) == (6, 20, 26)


def test_non_strict_mode_pools_ur_even_with_relaxation():
    r = evaluate_eligibility(Profile(AGE_28, Category.SC), Post(), strict_ur_migration=False)
    assert r.total_reachable_seats == 26


def test_ur_28_is_not_eligible():
    r = evaluate_eligibility(Profile(AGE_28, Category.UR), Post())
    assert not r.is_eligible
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


def test_branch_mismatch_blocks():
    r = evaluate_eligibility(Profile(date(2002, 1, 1), Category.UR, streams=["B.Tech Civil"]), Post())
    assert not r.is_eligible and r.qualification_match is False


@pytest.mark.parametrize(
    ("user", "post", "ok"),
    [
        ("B.Tech ECE", "B.E. (Electronics & Communication Engg.)", True),
        ("B.Tech ECE", "B.E./B.Tech Any Branch", True),
        ("B.Tech ECE", "Any Graduate", True),
        ("Diploma ECE", "Any Graduate", False),
        ("B.Tech EEE", "B.E./B.Tech Electrical", False),
        ("B.Tech CSE", "B.E./B.Tech Computer Science & Engineering", True),
        ("B.Sc Physics", "B.E./B.Tech Electronics", False),
    ],
)
def test_stream_matching(user, post, ok):
    r = evaluate_eligibility(
        Profile(date(2002, 1, 1), Category.UR, streams=[user]), Post(eligible_streams=[post])
    )
    assert r.qualification_match is ok


def test_unknown_qualification_does_not_block():
    r = evaluate_eligibility(Profile(date(2002, 1, 1), Category.UR), Post(eligible_streams=[]))
    assert r.is_eligible and r.qualification_match is None


def test_missing_vacancy_matrix():
    r = evaluate_eligibility(Profile(date(2002, 1, 1), Category.SC), Post(vacancy=None))
    assert r.is_eligible and r.total_reachable_seats == 0
