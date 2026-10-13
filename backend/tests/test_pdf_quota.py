"""Gemini quota handling: a daily quota isn't retried, the next model is tried,
and a PDF that couldn't be read for quota reasons goes back in the queue."""

import json
from types import SimpleNamespace

import pytest
from google.genai import errors as genai_errors

from app.core.config import get_settings
from app.domain.enums import ItemKind, ItemStatus
from app.models import DiscoveredItem
from app.services import pdf_parser
from app.services.discovery_pipeline import return_to_queue
from app.services.pdf_parser import GeminiQuotaExhausted, extract_notification

PDF = b"%PDF-1.4 fake notification"

EXTRACTION = {
    "organization": "Bharat Electronics Limited",
    "exam_name": "Probationary Engineer 2026",
    "advertisement_no": None,
    "official_portal_url": None,
    "application_start_date": "2026-10-01",
    "application_end_date": "2026-11-15",
    "application_end_time": None,
    "exam_date": None,
    "age_as_on_date": "2026-10-01",
    "fee_payment_last_date": None,
    "correction_window_start_date": None,
    "correction_window_end_date": None,
    "admit_card_release_date": None,
    "exam_end_date": None,
    "answer_key_date": None,
    "result_date": None,
    "general_age_relaxations": [],
    "posts": [
        {
            "post_code": None,
            "post_name": "Probationary Engineer",
            "min_age": None,
            "max_age_ur": 25,
            "age_as_on_date": None,
            "eligible_degrees": ["B.E./B.Tech"],
            "qualification_summary": None,
            "eligibility_text": None,
            "min_qualification_level": None,
            "open_to_any_graduate": None,
            "open_to_any_post_graduate": None,
            "min_experience_years": None,
            "vacancies": {
                "ur": 10,
                "sc": 3,
                "st": 1,
                "obc": 5,
                "ews": 2,
                "total": 21,
                "pwbd": None,
                "ex_serviceman": None,
            },  # fmt: skip
            "age_relaxations": [],
        }
    ],
}


def _quota_error(quota_id: str) -> genai_errors.APIError:
    return genai_errors.APIError(
        429,
        {
            "error": {
                "code": 429,
                "message": "You exceeded your current quota, please check your plan and billing details.",
                "status": "RESOURCE_EXHAUSTED",
                "details": [
                    {
                        "@type": "type.googleapis.com/google.rpc.QuotaFailure",
                        "violations": [{"quotaId": quota_id}],
                    }
                ],
            }
        },
    )


class FakeClient:
    """Stands in for genai.Client: per-model behaviour, counts calls."""

    def __init__(self, behaviour: dict[str, object]):
        self.behaviour = behaviour
        self.calls: list[str] = []
        self.aio = SimpleNamespace(models=SimpleNamespace(generate_content=self._generate))

    async def _generate(self, *, model, contents, config):
        self.calls.append(model)
        outcome = self.behaviour[model]
        if isinstance(outcome, Exception):
            raise outcome
        return SimpleNamespace(text=json.dumps(outcome), candidates=[])


@pytest.fixture(autouse=True)
def _fresh_model_state(monkeypatch):
    pdf_parser._unusable_models.clear()
    settings = get_settings()
    monkeypatch.setattr(settings, "gemini_model", "main-model")
    monkeypatch.setattr(settings, "gemini_fallback_models", "lite-model")
    monkeypatch.setattr(settings, "gemini_max_attempts", 3)
    yield
    pdf_parser._unusable_models.clear()


async def test_daily_quota_is_not_retried_and_the_fallback_model_reads_the_pdf():
    client = FakeClient(
        {
            "main-model": _quota_error("GenerateRequestsPerDayPerProjectPerModel-FreeTier"),
            "lite-model": EXTRACTION,
        }
    )
    parsed = await extract_notification(PDF, client=client)
    assert client.calls == ["main-model", "lite-model"]  # no retries of the daily-quota error
    assert parsed.extraction_model == "lite-model"
    assert parsed.posts[0].allowed_degrees == ["B_TECH"]

    # The exhausted model is skipped for the rest of the run.
    await extract_notification(PDF, client=client)
    assert client.calls == ["main-model", "lite-model", "lite-model"]


async def test_all_models_out_of_quota_raises_quota_exhausted():
    day = _quota_error("GenerateRequestsPerDayPerProjectPerModel-FreeTier")
    client = FakeClient({"main-model": day, "lite-model": day})
    with pytest.raises(GeminiQuotaExhausted):
        await extract_notification(PDF, client=client)
    with pytest.raises(GeminiQuotaExhausted):  # nothing left to try: no more calls
        await extract_notification(PDF, client=client)
    assert client.calls == ["main-model", "lite-model"]


async def test_unknown_fallback_model_is_skipped():
    missing = genai_errors.APIError(404, {"error": {"code": 404, "message": "models/x is not found"}})
    client = FakeClient({"main-model": EXTRACTION, "lite-model": missing})
    parsed = await extract_notification(PDF, client=client)
    assert parsed.extraction_model == "main-model"


def test_quota_failure_puts_the_pdf_back_in_the_queue():
    item = DiscoveredItem(
        kind=ItemKind.NOTIFICATION_PDF, status=ItemStatus.FAILED, attempts=1, error="Gemini API error 429"
    )
    return_to_queue(item)
    assert (item.status, item.attempts, item.error) == (ItemStatus.PENDING, 0, None)
