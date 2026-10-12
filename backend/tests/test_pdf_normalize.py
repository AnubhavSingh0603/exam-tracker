from zoneinfo import ZoneInfo

from app.schemas.extraction import NotificationExtraction
from app.services.pdf_parser import normalize_extraction

IST = ZoneInfo("Asia/Kolkata")


def _raw(**over) -> NotificationExtraction:
    vac = {"ur": 10, "sc": 3, "st": 1, "obc": 5, "ews": 2, "total": 21, "pwbd": None, "ex_serviceman": None}
    base = {
        "organization": "Bharat Electronics Limited",
        "exam_name": "Probationary Engineer 2026",
        "advertisement_no": "BEL/PE/2026/01",
        "official_portal_url": "www.bel-india.in",
        "application_start_date": "2026-10-01",
        "application_end_date": "15.11.2026",
        "application_end_time": "17:00",
        "exam_date": None,
        "age_as_on_date": "2026-10-01",
        "general_age_relaxations": [
            {"category": "OBC (NCL)", "years": 3},
            {"category": "SC/ST", "years": 5},
            {"category": "PwBD", "years": 10},
        ],
        "posts": [
            {
                "post_code": "PE-ECE",
                "post_name": "Probationary Engineer (E&C)",
                "min_age": None,
                "max_age_ur": 25,
                "age_as_on_date": None,
                "eligible_degrees": [
                    "B.E./B.Tech Electronics & Communication",
                    " b.e./b.tech electronics & communication ",
                ],
                "qualification_summary": None,
                "vacancies": vac,
                "age_relaxations": [],
            }
        ],
    }
    base.update(over)
    return NotificationExtraction.model_validate(base)


def test_happy_path():
    n = normalize_extraction(_raw(), tz=IST)
    assert n.application_deadline.isoformat() == "2026-11-15T17:00:00+05:30"
    assert n.portal_url == "https://www.bel-india.in"
    post = n.posts[0]
    assert post.age_relaxation_overrides == {"OBC": 3, "SC": 5, "ST": 5, "PWBD": 10}
    assert post.eligible_streams == ["B.E./B.Tech Electronics & Communication"]
    assert post.vacancy.total == 21
    assert not n.needs_review, n.review_notes


def test_seat_mismatch_flags_review():
    raw = _raw()
    raw.posts[0].vacancies.total = 30
    n = normalize_extraction(raw, tz=IST)
    assert n.needs_review
    assert any("printed total" in note for note in n.review_notes)


def test_missing_age_cutoff_falls_back_to_closing_date():
    n = normalize_extraction(_raw(age_as_on_date=None), tz=IST)
    assert n.posts[0].age_as_on.isoformat() == "2026-11-15"
    assert n.needs_review
