"""The recorded parity cases still match the Python engine (the Dart port is
checked against the same file in mobile/test/eligibility_parity_test.dart)."""

import json
from pathlib import Path

import pytest

from app.services.streams import infer_requirement
from tests.parity import evaluate_case

CASES = json.loads(
    (Path(__file__).resolve().parents[2] / "shared" / "eligibility_cases.json").read_text(encoding="utf-8")
)["cases"]


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
def test_python_engine_matches_recorded_case(case):
    assert evaluate_case(case["profile"], case["post"]) == case["expect"], (
        "Engine changed: run `python scripts/make_parity_cases.py`, then make the Dart port match"
    )


@pytest.mark.parametrize("case", CASES, ids=[c["name"] for c in CASES])
def test_cases_are_in_published_form(case):
    """Each post's degree lines imply nothing beyond its published fields (as publish.py emits)."""
    post = case["post"]
    req = infer_requirement(post["eligible_streams"])
    assert set(req.allowed_degrees) <= set(post["allowed_degrees"])
    assert not req.open_to_any_graduate or post["is_open_to_any_graduate"]
    assert not req.open_to_any_post_graduate or post["is_open_to_any_post_graduate"]
