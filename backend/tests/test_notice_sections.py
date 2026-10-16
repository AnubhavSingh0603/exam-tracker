"""Admit Card / Answer Key / Result sections become notices, with the official link."""

import json
from types import SimpleNamespace

from app.domain.enums import ExamMilestone
from app.services.discovery_pipeline import notice_kind, notice_section
from app.services.publish import _section_milestone
from app.services.scraper_service import (
    SECTION_FLAG,
    find_notice_link,
    notice_key,
    parse_wordpress_posts,
    section_milestone,
)

PAGE = """
<html><head><title>SSC CGL Tier 1 Admit Card 2026 - Sarkari Result</title></head><body>
<table><tr><td>
  <table>
    <tr><td>SSC CGL Tier 1 Admit Card 2026</td><td>Exam 30 Sep - 30 Oct 2026</td></tr>
    <tr><td>Join Telegram Channel</td><td><a href="https://t.me/sarkariresult">Click Here</a></td></tr>
    <tr><td>Download Admit Card</td><td><a href="https://ssc.gov.in/login?tab=admit">Click Here</a></td></tr>
    <tr><td>Check Exam City</td><td><a href="https://sarkariresult.com.cm/ssc-cgl/">More</a></td></tr>
    <tr><td>Official Website</td><td><a href="https://ssc.gov.in/">Click Here</a></td></tr>
  </table>
</td></tr></table>
</body></html>
"""


def test_section_sources():
    assert section_milestone("https://www.sarkariresult.com/admitcard/") == "admit_card"
    assert section_milestone("https://sarkariresult.com.cm/admit-card/") == "admit_card"
    assert section_milestone("https://sarkariresult.com.cm/answer-key/") == "answer_key"
    assert section_milestone("https://sarkariresult.com.cm/result/") == "result"
    assert section_milestone("https://sarkariresult.com.cm/latest-jobs/") is None
    assert section_milestone("https://www.freejobalert.com/latest-notifications/") is None


def test_the_official_link_from_the_page():
    url = find_notice_link(PAGE, "https://sarkariresult.com.cm/ssc-cgl-admit-card-2026/", "admit_card")
    assert url == "https://ssc.gov.in/login?tab=admit"  # not Telegram, not back into the aggregator


def test_no_matching_row_means_no_link():
    assert find_notice_link(PAGE, "https://sarkariresult.com.cm/x/", "result") is None
    assert find_notice_link("<html><body>nothing</body></html>", "https://x/", "answer_key") is None


def test_the_section_is_remembered_on_the_notice():
    item = SimpleNamespace(keywords=["admit_card", f"{SECTION_FLAG}answer_key"])
    assert notice_section(item) == "answer_key"
    assert _section_milestone(item) is ExamMilestone.ANSWER_KEY
    assert _section_milestone(SimpleNamespace(keywords=[])) is None


def test_api_seeds_carry_their_section():
    url = "https://sarkariresult.com.cm/wp-json/wp/v2/posts?categories=4&per_page=50&section=answer-key"
    assert section_milestone(url) == "answer_key"


def test_notice_keys_tell_stages_of_one_page_apart():
    assert notice_key("SSC CGL Tier-I Admit Card 2026", "admit_card") == "admit_card-tier-i"
    assert notice_key("SSC CGL Tier-II Admit Card 2026", "admit_card") == "admit_card-tier-ii"
    assert notice_key("SBI PO Mains Result 2026", "result") == "result-mains"
    # Filed under Results, but the post is an answer key.
    assert notice_key("RRB Section Controller Answer Key 2026 – Out", "result") == "answer_key"
    assert notice_key("UPSC Principal Exam Date 2026", "admit_card") == "exam_date"


def test_wordpress_posts_become_notices():
    body = json.dumps(
        [
            {
                "id": 1,
                "date": "2026-10-16T16:53:11",
                "modified": "2026-10-16T17:00:00",
                "link": "https://sarkariresult.com.cm/ssc-cgl-2026/",
                "title": {"rendered": "SSC CGL Tier-I Admit Card 2026 &#8211; Out"},
            },
            {"id": 2, "link": "", "title": {"rendered": "broken"}},
        ]
    )
    base = "https://sarkariresult.com.cm/wp-json/wp/v2/posts?categories=3&section=admit-card"
    [link] = parse_wordpress_posts(body, base)
    assert link.url == "https://sarkariresult.com.cm/ssc-cgl-2026/?notice=admit_card-tier-i"
    assert link.title == "SSC CGL Tier-I Admit Card 2026 – Out"
    assert link.detail_page and link.published_at is not None


def test_the_posts_own_kind_picks_the_link_row():
    item = SimpleNamespace(
        url="https://sarkariresult.com.cm/rrb-sc-2026/?notice=answer_key", keywords=[f"{SECTION_FLAG}result"]
    )
    assert notice_kind(item) == "answer_key"
    dated = SimpleNamespace(url="https://x/p/?notice=exam_date", keywords=[f"{SECTION_FLAG}admit_card"])
    assert notice_kind(dated) == "admit_card"
