import uuid
from datetime import UTC, date, datetime

import pytest

from app.core.config import get_settings
from app.domain.enums import ApplicationStatus, ExamMilestone, UpdateSource
from app.models import ExamUpdateLog, JobPost, UserApplication
from app.services.exam_watcher import (
    advance_status,
    check_exam_updates,
    classify_milestone,
    detect_updates,
    extract_event_date,
    is_exam_specific_page,
    names_this_exam,
    push_text,
)
from app.services.http_fetcher import FetchError, FetchResult
from app.services.scraper_service import Link, parse_generic

NOW = datetime(2026, 12, 1, 6, 0, tzinfo=UTC)
SSC = "Staff Selection Commission"
CGL = "Combined Graduate Level Examination 2026"

NOTICE_BOARD = """
<table>
 <tr><td>28/11/2026</td><td><a href="/notices/cgl26-admit.pdf">SSC CGL 2026 Tier-I Admit Card (Exam on 14.12.2026)</a></td></tr>
 <tr><td>27/11/2026</td><td><a href="/notices/chsl26-admit.pdf">SSC CHSL 2026 Admit Card</a></td></tr>
 <tr><td>20/11/2026</td><td><a href="/notices/cgl25-result.pdf">SSC CGL 2025 Final Result</a></td></tr>
 <tr><td>01/09/2026</td><td><a href="/notices/cgl26-notice.pdf">SSC CGL 2026 Notification</a></td></tr>
 <tr><td>25/11/2026</td><td><a href="/notices/cgl26-city.pdf">Combined Graduate Level Exam 2026: Exam City Intimation Slip</a></td></tr>
</table>
"""


def _links(html: str = NOTICE_BOARD, base: str = "https://ssc.gov.in/") -> list[Link]:
    return parse_generic(html, base)


# --- pure detection --------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "milestone"),
    [
        ("SSC CGL Tier-I Admit Card / Hall Ticket Download", ExamMilestone.ADMIT_CARD),
        ("Call Letter for Document Verification", ExamMilestone.ADMIT_CARD),
        ("Exam Date announced for CEN 03/2026", ExamMilestone.EXAM_SCHEDULE),
        ("Exam City Intimation Slip", ExamMilestone.EXAM_SCHEDULE),
        ("Tier-II exam postponed", ExamMilestone.POSTPONED),
        ("Rescheduled Admit Card for Shift 2", ExamMilestone.POSTPONED),
        ("Tentative Answer Key and Objection Tracker", ExamMilestone.ANSWER_KEY),
        ("Uploading of Response Sheets", ExamMilestone.ANSWER_KEY),
        ("Final Result with Category-wise Cut-off Marks", ExamMilestone.RESULT),
        ("Merit List of selected candidates", ExamMilestone.RESULT),
        ("Detailed Notification for recruitment", None),
    ],
)
def test_classify_milestone(text, milestone):
    assert classify_milestone(text) is milestone


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("Exam on 14.12.2026", date(2026, 12, 14)),
        ("scheduled from 3rd March 2027", date(2027, 3, 3)),
        ("Admit card released", None),
    ],
)
def test_extract_event_date(text, expected):
    assert extract_event_date(text) == expected


def test_other_years_of_the_same_exam_are_ignored():
    assert names_this_exam("SSC CGL 2026 Admit Card", "SSC CGL 2026", SSC)
    assert not names_this_exam("SSC CGL 2025 Result", "SSC CGL 2026", SSC)


@pytest.mark.parametrize(
    ("url", "specific"),
    [
        ("https://ssc.gov.in/", False),
        ("https://ssc.gov.in/notices", False),
        ("https://www.rrbcdg.gov.in/cen-03-2026", True),
        ("https://bel-india.in/careers/pe-2026/", True),
    ],
)
def test_exam_specific_page(url, specific):
    assert is_exam_specific_page(url) is specific


def test_detect_updates_on_a_board_notice_page():
    found = detect_updates(
        _links(),
        exam_name=CGL,
        organization=SSC,
        source=UpdateSource.OFFICIAL,
        exam_specific_page=False,
        known_urls=set(),
    )
    assert [(u.milestone, u.url.rsplit("/", 1)[1]) for u in found] == [
        (ExamMilestone.ADMIT_CARD, "cgl26-admit.pdf"),
        (ExamMilestone.EXAM_SCHEDULE, "cgl26-city.pdf"),
    ]
    assert found[0].event_date == date(2026, 12, 14)


def test_known_urls_are_not_new():
    known = {"https://ssc.gov.in/notices/cgl26-admit.pdf"}
    found = detect_updates(
        _links(), exam_name=CGL, organization=SSC, source=UpdateSource.OFFICIAL,
        exam_specific_page=False, known_urls=known,
    )  # fmt: skip
    assert [u.milestone for u in found] == [ExamMilestone.EXAM_SCHEDULE]


def test_exam_specific_page_accepts_unnamed_notices():
    html = '<ul><li><a href="/dl/admit">Download Admit Card</a></li><li><a href="/faq">FAQ</a></li></ul>'
    found = detect_updates(
        _links(html, "https://www.rrbcdg.gov.in/cen-03-2026/"),
        exam_name="RRB NTPC CEN 03/2026",
        organization="Railway Recruitment Board",
        source=UpdateSource.OFFICIAL,
        exam_specific_page=True,
        known_urls=set(),
    )
    assert [u.milestone for u in found] == [ExamMilestone.ADMIT_CARD]


def test_status_only_moves_forward():
    s = ApplicationStatus
    assert advance_status(s.APPLIED, [ExamMilestone.ADMIT_CARD]) is s.ADMIT_CARD_LIVE
    assert advance_status(s.ANSWER_KEY_LIVE, [ExamMilestone.ADMIT_CARD]) is s.ANSWER_KEY_LIVE
    assert advance_status(s.EXAM_SCHEDULED, [ExamMilestone.POSTPONED]) is s.EXAM_SCHEDULED
    assert advance_status(s.APPLIED, [ExamMilestone.RESULT, ExamMilestone.ANSWER_KEY]) is s.RESULT_DECLARED


def test_push_text():
    entry = ExamUpdateLog(milestone=ExamMilestone.RESULT, title="SSC CGL 2026 Final Result", url="u")
    assert push_text(entry, "SSC CGL 2026") == (
        "🏁 Result declared: SSC CGL 2026",
        "SSC CGL 2026 Final Result",
    )


# --- one application, end to end (fake fetcher) ------------------------------------------


class FakeFetcher:
    def __init__(self, pages: dict[str, str | Exception]):
        self.pages = pages
        self.calls: list[str] = []

    async def get(self, url, *, max_bytes):
        self.calls.append(url)
        page = self.pages[url]
        if isinstance(page, Exception):
            raise page
        return FetchResult(
            url=url, status=200, content_type="text/html", body=page.encode(), encoding="utf-8"
        )


def _application(**kw) -> UserApplication:
    job = JobPost(id=uuid.uuid4(), organization=SSC, exam_name=CGL)
    job.timeline = None
    base = dict(
        id=uuid.uuid4(),
        exam_name=CGL,
        organization=SSC,
        official_portal_url="https://ssc.gov.in/",
        status=ApplicationStatus.APPLIED,
        updates=[],
        job=job,
    )
    base.update(kw)
    return UserApplication(**base)


async def test_check_exam_updates_advances_status_and_fills_timeline():
    app = _application()
    fetcher = FakeFetcher({"https://ssc.gov.in/": NOTICE_BOARD})
    aggregator = [Link(url="https://agg.example/cgl-2026-answer-key", title="SSC CGL 2026 Answer Key Out")]
    logs = await check_exam_updates(
        app, fetcher=fetcher, aggregator_links=aggregator, portal_cache={}, now=NOW, settings=get_settings()
    )
    assert [(entry.milestone, entry.source) for entry in logs] == [
        (ExamMilestone.ADMIT_CARD, UpdateSource.OFFICIAL),
        (ExamMilestone.EXAM_SCHEDULE, UpdateSource.OFFICIAL),
        (ExamMilestone.ANSWER_KEY, UpdateSource.AGGREGATOR),
    ]
    assert app.status is ApplicationStatus.ANSWER_KEY_LIVE
    assert app.last_checked_at == NOW and app.last_check_error is None
    t = app.job.timeline
    assert t.admit_card_url.endswith("cgl26-admit.pdf")
    assert t.exam_city_slip_url.endswith("cgl26-city.pdf")
    assert t.answer_key_url == "https://agg.example/cgl-2026-answer-key"
    assert all(entry.notified_at is None for entry in logs)  # queued for dispatch

    # Second run: nothing new.
    again = await check_exam_updates(
        app, fetcher=fetcher, aggregator_links=aggregator, portal_cache={}, now=NOW, settings=get_settings()
    )
    assert again == []


async def test_portal_is_fetched_once_per_run_and_errors_are_recorded():
    fetcher = FakeFetcher({"https://ssc.gov.in/": FetchError("HTTP 503")})
    cache: dict = {}
    a, b = _application(), _application(job=None)
    for app in (a, b):
        await check_exam_updates(
            app, fetcher=fetcher, aggregator_links=[], portal_cache=cache, now=NOW, settings=get_settings()
        )
    assert fetcher.calls == ["https://ssc.gov.in/"]
    assert "HTTP 503" in a.last_check_error and "HTTP 503" in b.last_check_error
    assert a.status is ApplicationStatus.APPLIED


async def test_manual_exam_without_portal_uses_aggregators_only():
    app = _application(official_portal_url=None, job=None)
    aggregator = [Link(url="https://agg.example/r", title="SSC CGL 2026 Result Declared")]
    logs = await check_exam_updates(
        app,
        fetcher=FakeFetcher({}),
        aggregator_links=aggregator,
        portal_cache={},
        now=NOW,
        settings=get_settings(),
    )
    assert [entry.milestone for entry in logs] == [ExamMilestone.RESULT]
    assert app.status is ApplicationStatus.RESULT_DECLARED
