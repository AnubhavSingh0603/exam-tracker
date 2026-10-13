"""Regenerate shared/eligibility_cases.json from the Python eligibility engine.

    cd backend && python scripts/make_parity_cases.py

The phone runs a Dart port of app/services/eligibility.py. Both test suites
(tests/test_parity.py and mobile/test/eligibility_parity_test.dart) evaluate
these cases and must reproduce the expectations recorded here, so the two
implementations can't drift apart. Posts are in the published (jobs.json) form.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))
CASES_FILE = BACKEND.parent / "shared" / "eligibility_cases.json"

from tests.parity import evaluate_case  # noqa: E402

AS_ON = "2026-10-01"
VAC = {"ur": 20, "sc": 6, "st": 3, "obc": 11, "ews": 4, "total": 44}


def profile(**kw):
    base = {
        "date_of_birth": "2002-01-01",
        "category": "UR",
        "qualification_tier": "UG",
        "degree_title": "B_TECH",
        "custom_qualification_text": None,
        "experience_years": 0.0,
        "is_pwbd": False,
        "is_ex_serviceman": False,
        "ex_serviceman_service_years": 0,
    }
    base.update(kw)
    return base


def post(**kw):
    base = {
        "min_age": 18,
        "base_max_age": 25,
        "age_as_on": AS_ON,
        "eligible_streams": ["B.E./B.Tech"],
        "qualification_text": None,
        "raw_eligibility_text": None,
        "allowed_degrees": ["B_TECH"],
        "min_qualification_level": "UG",
        "is_open_to_any_graduate": False,
        "is_open_to_any_post_graduate": False,
        "min_experience_years": 0.0,
        "age_relaxation_overrides": {},
        "vacancy": VAC,
    }
    base.update(kw)
    return base


ANY_GRAD = {"eligible_streams": ["Any graduate"], "allowed_degrees": [], "is_open_to_any_graduate": True}

CASES = [
    ("direct degree match", profile(), post()),
    (
        "sc 28 eligible via relaxation: quota seats only",
        profile(date_of_birth="1998-06-15", category="SC"),
        post(),
    ),
    ("sc young: ur + quota", profile(category="SC"), post()),
    ("ur 28 too old", profile(date_of_birth="1998-06-15"), post()),
    ("obc + pwbd stack", profile(date_of_birth="1988-01-01", category="OBC", is_pwbd=True), post()),
    ("ews gets no relaxation", profile(date_of_birth="2000-01-01", category="EWS"), post()),
    (
        "ex-serviceman adds service years",
        profile(date_of_birth="1994-01-01", is_ex_serviceman=True, ex_serviceman_service_years=6),
        post(),
    ),
    (
        "notification override wins",
        profile(date_of_birth="1998-06-15", category="OBC"),
        post(age_relaxation_overrides={"OBC": 5}),
    ),
    ("below minimum age", profile(date_of_birth="2010-01-01"), post()),
    ("no age cut-off: not verified but shown", profile(), post(age_as_on=None)),
    ("other degree blocked", profile(degree_title="B_SC"), post()),
    ("m.tech implies b.tech", profile(qualification_tier="PG", degree_title="M_TECH"), post()),
    ("any graduate: b.a.", profile(degree_title="B_A"), post(**ANY_GRAD)),
    (
        "any graduate: diploma blocked",
        profile(qualification_tier="DIPLOMA", degree_title="DIPLOMA"),
        post(**ANY_GRAD),
    ),
    (
        "any pg: ug blocked",
        profile(),
        post(
            eligible_streams=[],
            allowed_degrees=[],
            min_qualification_level="PG",
            is_open_to_any_post_graduate=True,
        ),
    ),
    (
        "any pg: mba",
        profile(qualification_tier="PG", degree_title="MBA"),
        post(
            eligible_streams=[],
            allowed_degrees=[],
            min_qualification_level="PG",
            is_open_to_any_post_graduate=True,
        ),
    ),
    (
        "12th post cascades to graduates",
        profile(degree_title="B_COM"),
        post(
            eligible_streams=["12th pass"],
            allowed_degrees=["CLASS_12"],
            min_qualification_level="INTERMEDIATE",
        ),
    ),
    (
        "12th post does not cascade to diploma",
        profile(qualification_tier="DIPLOMA", degree_title="DIPLOMA"),
        post(
            eligible_streams=["12th pass"],
            allowed_degrees=["CLASS_12"],
            min_qualification_level="INTERMEDIATE",
        ),
    ),
    (
        "10th post cascades to iti",
        profile(qualification_tier="DIPLOMA", degree_title="ITI"),
        post(eligible_streams=["10th pass"], allowed_degrees=["CLASS_10"], min_qualification_level="MATRIC"),
    ),
    (
        "10th + iti trade post does not cascade",
        profile(degree_title="B_A"),
        post(eligible_streams=["10th + ITI"], allowed_degrees=["ITI"], min_qualification_level="DIPLOMA"),
    ),
    (
        "needs higher tier",
        profile(),
        post(eligible_streams=["M.Tech"], allowed_degrees=["M_TECH"], min_qualification_level="PG"),
    ),
    (
        "nothing machine-readable: unverified",
        profile(),
        post(eligible_streams=[], allowed_degrees=[], min_qualification_level=None),
    ),
    (
        "level only: unverified",
        profile(),
        post(eligible_streams=[], allowed_degrees=[], min_qualification_level="UG"),
    ),
    (
        "others found in eligibility text",
        profile(degree_title="OTHERS", custom_qualification_text="B.Des"),
        post(
            eligible_streams=["B.Des"],
            allowed_degrees=[],
            raw_eligibility_text="Bachelor's Degree in Design (B.Des) from a recognised institute.",
        ),
    ),
    (
        "others with alternatives",
        profile(degree_title="OTHERS", custom_qualification_text="CA/CS"),
        post(eligible_streams=[], allowed_degrees=[], raw_eligibility_text="Qualified CA or ICWA"),
    ),
    (
        "others not mentioned",
        profile(degree_title="OTHERS", custom_qualification_text="BVSc"),
        post(eligible_streams=["BAMS"], allowed_degrees=[], raw_eligibility_text="BAMS degree"),
    ),
    (
        "others with no text in post: unverified",
        profile(degree_title="OTHERS", custom_qualification_text="BVSc"),
        post(eligible_streams=[], allowed_degrees=[], min_qualification_level=None),
    ),
    ("experience met", profile(experience_years=2.0), post(min_experience_years=2.0)),
    ("half a year short: suggested", profile(experience_years=1.5), post(min_experience_years=2.0)),
    ("fresher 3 years short: hidden", profile(), post(min_experience_years=3.0)),
    ("missing vacancy matrix", profile(category="SC"), post(vacancy=None)),
]


def main() -> None:
    cases = [{"name": name, "profile": p, "post": q, "expect": evaluate_case(p, q)} for name, p, q in CASES]
    CASES_FILE.parent.mkdir(exist_ok=True)
    CASES_FILE.write_text(json.dumps({"cases": cases}, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {len(cases)} cases to {CASES_FILE}")


if __name__ == "__main__":
    main()
