import json
from datetime import UTC, date, datetime, timedelta

from app.core.config import get_settings
from app.domain.enums import ItemKind
from app.services.scraper_service import (
    Link,
    canonical_url,
    classify,
    closed_note,
    closing_date,
    find_apply_link,
    fingerprint,
    flag_keywords,
    next_check_time,
    parse_free_job_alert_detail,
    parse_free_job_alert_list,
    parse_generic,
    parse_sarkari_result_detail,
    parse_sarkari_result_list,
    parse_ssc_api,
)

SR_LIST = """
<nav><ul><li><a href="/admitcard/">Admit Card</a></li></ul></nav>
<ul class="wp-block-list">
  <li><a href="https://www.sarkariresult.com/2026/assam-rifles-rally-sep26/">Assam Rifles Rally Recruitment Online Form 2026</a> | Last Date : 28/10/2026</li>
  <li><a href="https://www.sarkariresult.com/2026/isro-various-post-jul26/">ISRO ICRB Assistant and Other Post Admit Card 2026</a></li>
  <li><a href="https://www.sarkariresult.com/2026/upsc-cse-result/">UPSC Civil Services Final Result 2025</a></li>
  <li><a href="https://example.com/ad">Sponsored</a></li>
</ul>"""

SR_DETAIL = """<title>Assam Rifles Rally Recruitment Online Form 2026</title>
<table>
 <tr><td>Apply Online</td><td><a href="https://www.assamrifles.gov.in/onlineapp/Default.aspx">Click Here</a></td></tr>
 <tr><td>Download Notification</td><td><a href="https://www.sarkariresult.com/wp-content/uploads/2026/09/df021abc">Click Here</a></td></tr>
</table>"""

FJA_LIST = """<table class="lattbl">
 <tr><th>Post Date</th><th>Recruitment Board</th><th>Exam / Post Name</th><th>Qualification</th><th>Advt No</th><th>Last Date</th><th>More Information</th></tr>
 <tr><td>10/10/2026</td><td>Exim Bank</td><td>Deputy Manager &amp; Manager</td><td>CA, MBA/PGDM</td>
     <td>HRM/DM &amp; M/SRD/2026-27/04</td><td>21-10-2026</td>
     <td><a href="https://www.freejobalert.com/articles/exim-bank-recruitment-2026-3066646">Get Details</a></td></tr>
</table>"""

FJA_DETAIL = """<title>Exim Bank Recruitment 2026</title>
<a href="https://www.eximbankindia.in/sites/default/files/2026-09/Detailed%20SRD%20Advertisement.pdf">Download Official Notification</a>
<a href="https://www.freejobalert.com/latest-notifications/">Latest Notifications</a>"""

SSC_JSON = json.dumps(
    {
        "statusCode": "200",
        "data": [
            {
                "headline": "Junior Engineer Examination, 2026: Notice of Examination",
                "createdAt": "2026-10-08T07:43:05.605Z",
                "attachments": [
                    {
                        "type": "application/pdf",
                        "path": "uploads\\masterData\\NoticeBoards\\JE_Notice_2026.pdf",
                    }
                ],
            }
        ],
    }
)

GENERIC = """
<header><a href="/careers">Careers</a></header>
<table>
 <tr><td>Advt No. 05/2026 – Recruitment of Engineers (Electronics)</td><td><a href="/docs/advt-05-2026.pdf">Download</a></td></tr>
 <tr><td>Answer Key – Assistant Exam</td><td><a href="/docs/answer-key.pdf">Download</a></td></tr>
 <tr><td>Corrigendum to Advt No. 04/2026</td><td><a href="/docs/corr-04.pdf?utm_source=x#top">Download</a></td></tr>
</table>"""


def kinds(links):
    return [classify(lk)[0] for lk in links]


def test_sarkari_result_list_keeps_only_own_detail_pages_and_classifies():
    links = parse_sarkari_result_list(SR_LIST, "https://www.sarkariresult.com/latestjob/")
    assert len(links) == 3  # nav + external ad dropped
    assert kinds(links) == [ItemKind.DETAIL_PAGE, ItemKind.ALERT, ItemKind.OTHER]
    assert "Last Date : 28/10/2026" in links[0].context


SR_DETAIL_LAYOUT = """<title>UPSSSC Forest Guard Fee Payment</title>
<table><tr><td><table>
  <tr><td>Important Notification Links</td><td><a href="https://www.sarkariresult.com/">Home</a></td></tr>
  <tr><td>Download Notification</td><td><a href="https://www.sarkariresult.com/category/upsssc/">More</a></td></tr>
</table></td></tr></table>"""


def test_sarkari_result_detail_ignores_links_back_into_the_site():
    # Found live: some pages only link home/categories next to "notification".
    assert parse_sarkari_result_detail(SR_DETAIL_LAYOUT, "https://www.sarkariresult.com/x/") == []


def test_tentative_vacancy_notice_is_not_queued_for_gemini():
    link = Link(
        "https://ssc.gov.in/api/attachment/x.pdf", "Tentative Vacancies of Junior Engineer Examination, 2026."
    )
    assert classify(link)[0] is ItemKind.OTHER


def test_sarkari_result_detail_finds_notification_row_without_pdf_extension():
    links = parse_sarkari_result_detail(
        SR_DETAIL, "https://www.sarkariresult.com/2026/assam-rifles-rally-sep26/"
    )
    assert [lk.url for lk in links] == ["https://www.sarkariresult.com/wp-content/uploads/2026/09/df021abc"]
    assert links[0].pdf_hint and classify(links[0])[0] is ItemKind.NOTIFICATION_PDF


def test_free_job_alert_rows_and_detail():
    rows = parse_free_job_alert_list(FJA_LIST, "https://www.freejobalert.com/latest-notifications/")
    assert len(rows) == 1
    row = rows[0]
    assert row.title.startswith("Exim Bank – Deputy Manager & Manager Recruitment")
    assert row.published_at == datetime(2026, 10, 10, tzinfo=UTC)
    assert classify(row)[0] is ItemKind.DETAIL_PAGE

    pdfs = parse_free_job_alert_detail(FJA_DETAIL, row.url)
    assert len(pdfs) == 1 and pdfs[0].url.startswith("https://www.eximbankindia.in/")


def test_ssc_api_builds_attachment_urls():
    links = parse_ssc_api(SSC_JSON, "https://ssc.gov.in/api/...")
    assert (
        links[0].url == "https://ssc.gov.in/api/attachment/uploads/masterData/NoticeBoards/JE_Notice_2026.pdf"
    )
    assert links[0].published_at == datetime(2026, 10, 8, 7, 43, 5, 605000, tzinfo=UTC)
    assert classify(links[0])[0] is ItemKind.OTHER  # a notice, but not a recruitment notification


def test_generic_parser_uses_row_context_and_skips_chrome():
    links = parse_generic(GENERIC, "https://careers.example.org/jobs")
    by_url = {lk.url: lk for lk in links}
    assert "https://careers.example.org/careers" not in by_url
    advt = by_url["https://careers.example.org/docs/advt-05-2026.pdf"]
    assert classify(advt)[0] is ItemKind.NOTIFICATION_PDF
    assert classify(by_url["https://careers.example.org/docs/answer-key.pdf"])[0] is ItemKind.OTHER
    corr = by_url["https://careers.example.org/docs/corr-04.pdf"]  # utm + fragment stripped
    assert classify(corr) == (ItemKind.ALERT, ["corrigendum"])


def test_keyword_flags_cover_spec_terms():
    assert flag_keywords("SSC CGL Admit Card released") == ["admit_card"]
    assert flag_keywords("Exam Date announced") == ["exam_date"]
    assert flag_keywords("Prelims POSTPONED") == ["postponed"]
    assert flag_keywords("Corrigendum regarding age") == ["corrigendum"]
    assert flag_keywords("Last date extended till 30/10") == ["date_extended"]


def test_keywords_are_whole_words():
    # Found live on SarkariResult: a job *title* must not look like a date extension.
    assert flag_keywords("Bihar BTSC Food Safety Extension Officer Online form 2026") == []
    assert flag_keywords("Hall Ticket download") == ["admit_card"]
    assert flag_keywords("Unpostponedness") == []


def test_canonical_url():
    assert (
        canonical_url("HTTPS://Example.ORG/a.pdf?utm_source=x&id=3#frag") == "https://example.org/a.pdf?id=3"
    )


def test_fingerprint_is_order_independent_and_change_sensitive():
    a, b = Link("https://x/1", "One"), Link("https://x/2", "Two")
    assert fingerprint([a, b]) == fingerprint([b, a])
    assert fingerprint([a, b]) != fingerprint([a, b, Link("https://x/3", "Three")])


def test_next_check_time_jitter_and_backoff():
    s = get_settings()
    now = datetime(2026, 10, 11, tzinfo=UTC)
    for _ in range(50):
        delta = next_check_time(now, s) - now
        assert (
            timedelta(hours=4) - timedelta(minutes=30) <= delta <= timedelta(hours=4) + timedelta(minutes=30)
        )
    assert next_check_time(now, s, failures=10) - now <= timedelta(hours=24, minutes=30)


CM_LIST = """
<ul class="latest-posts-last-date">
  <li><a href="https://sarkariresult.com.cm/upsssc-je-2026/">UPSSSC Junior Engineer JE Online Form 2026 (1156 Posts)</a> – Last Date: 25 November 2026</li>
  <li><a href="https://sarkariresult.com.cm/ssc-gd-constable-2026/">SSC GD Constable Result 2026 – Out</a></li>
  <li><a href="https://example.org/elsewhere/">Not this site</a></li>
</ul>
"""
CM_DETAIL = """<title>SSC CGL 2026</title><table>
 <tr><td>Download Exam Date Notice</td><td><a href="https://ssc.gov.in/notice.pdf">Click Here</a></td></tr>
 <tr><td>Download Official Notification</td><td><a href="https://ssc.gov.in/Notice_of_adv_cgl_2026.pdf">Click Here</a></td></tr>
 <tr><td>Official Sarkari Result Website</td><td><a href="https://sarkariresult.com.cm/">Click Here</a></td></tr>
</table>"""


def test_unofficial_sarkari_result_copy_is_parsed_like_the_original():
    links = parse_sarkari_result_list(CM_LIST, "https://sarkariresult.com.cm/latest-jobs/")
    assert [lk.url for lk in links] == [
        "https://sarkariresult.com.cm/upsssc-je-2026/",
        "https://sarkariresult.com.cm/ssc-gd-constable-2026/",
    ]
    assert kinds(links) == [ItemKind.DETAIL_PAGE, ItemKind.OTHER]
    pdfs = parse_sarkari_result_detail(CM_DETAIL, "https://sarkariresult.com.cm/ssc-cgl-2026/")
    assert [lk.url for lk in pdfs] == ["https://ssc.gov.in/Notice_of_adv_cgl_2026.pdf"]


def test_closed_jobs_are_spotted_from_the_last_date_beside_the_link():
    """Reading a closed job's PDF would spend a Gemini request on nothing."""
    sr = parse_sarkari_result_list(SR_LIST, "https://www.sarkariresult.com/latestjob/")[0]
    assert closing_date(f"{sr.title} {sr.context}") == date(2026, 10, 28)
    fja = parse_free_job_alert_list(FJA_LIST, "https://www.freejobalert.com/latest-notifications/")[0]
    assert closing_date(fja.context) == date(2026, 10, 21)
    cm = parse_sarkari_result_list(CM_LIST, "https://sarkariresult.com.cm/latest-jobs/")[0]
    assert closing_date(cm.title) == date(2026, 11, 25)

    assert closing_date("SSC GD Last Date Extended till 30-11-2026") == date(2026, 11, 30)
    assert closing_date("Last Date: 1st Dec, 2026") == date(2026, 12, 1)
    assert closing_date("Last Date: Notify Soon") is None
    assert closing_date("Posted on 05/10/2026") is None  # a date, but not the last date

    today = date(2026, 10, 22)
    assert closed_note(fja.context, today) == "Closed on 21 Oct 2026 before it was read"
    assert closed_note("Last date 22/10/2026", today) is None  # open until the day ends
    assert closed_note(sr.context, today) is None


# Shapes copied from live pages (Oct 2026).
CM_LINKS = """<table><tbody>
 <tr><td><h5>Apply Online Link</h5></td>
     <td><h5><a href="https://sso.rajasthan.gov.in/signin?encq=6JkTF7D/fPuyiLpq+ts=">Click Here</a></h5></td></tr>
 <tr><td><h5>Check Official Notification</h5></td>
     <td><h5><a href="https://jankalyanfile.rajasthan.gov.in/O_270726.pdf">Click Here</a></h5></td></tr>
 <tr><td><h5>Check Sarkari Result</h5></td><td><h5><a href="https://sarkariresult.com.cm/">Click Here</a></h5></td></tr>
</tbody></table>"""
FJA_LINKS = """<article>
 <p><strong><a href="https://www.eximbankindia.in/files/Advertisement.pdf">Download Official Notification</a> |
   <a href="https://ibpsreg.ibps.in/iebsrdaug26/">Apply Online</a></strong></p>
 <ol><li><a href="iit-bhu-field-worker-recruitment-2026-apply-online-3072979">IIT (BHU) Recruitment 2026 – Apply Online</a></li></ol>
</article>
<ul><li>Apply Online: <a href="https://ibpsreg.ibps.in/iebsrdaug26/">Click here</a></li>
    <li>Official Website: <a href="https://www.eximbankindia.in">Click here</a></li></ul>"""


def test_apply_online_link_is_the_registration_page_not_the_portal():
    assert (
        find_apply_link(CM_LINKS, "https://sarkariresult.com.cm/rajasthan-safai-karmchari-2026/")
        == "https://sso.rajasthan.gov.in/signin?encq=6JkTF7D/fPuyiLpq+ts="
    )
    fja_page = "https://www.freejobalert.com/articles/exim-bank-recruitment-2026-3066646"
    assert find_apply_link(FJA_LINKS, fja_page) == "https://ibpsreg.ibps.in/iebsrdaug26/"

    # Several links in one row: each is judged by its own text, not the row's.
    row = """<table><tr><td>Apply Online</td><td><a href="https://ibps.in/">Official Website</a>
             <a href="https://ibpsonline.ibps.in/crpcl/">Registration</a> | <a href="https://x.in/login">Login</a></td></tr></table>"""
    assert find_apply_link(row, "https://www.sarkariresult.com/x/") == "https://ibpsonline.ibps.in/crpcl/"

    # Not live yet, or only an ad: no link (the app falls back to the official website).
    soon = "<table><tr><td>Apply Online</td><td><a href='#'>Link Activate Soon</a></td></tr></table>"
    assert find_apply_link(soon, "https://sarkariresult.com.cm/x/") is None
    ad = "<p><a href='https://mocktests.example.com/'>Free Mock Test – Register Now</a></p>"
    assert find_apply_link(ad, "https://sarkariresult.com.cm/x/") is None


def test_big_recruitments_are_read_before_walk_ins():
    from app.services.scraper_service import is_social_link, job_priority

    titles = [
        "Tata Memorial Centre- ACTREC Gardener",
        "IIIT Sri City Junior Research Fellow Recruitment 2026",
        "RRB NTPC Graduate Level Online Form 2026 (3548 Posts) – Last Date: 06 November 2026",
        "Notification for Common Recruitment Process for CRP- PO/MTs-XVI",
        "NHM Sukma Recruitment 2026 – Walkin for 53 Nursing Officer",
    ]
    ranked = sorted(titles, key=job_priority, reverse=True)
    assert set(ranked[:2]) == {titles[2], titles[3]}
    assert ranked[-1] == titles[0]
    assert is_social_link("https://whatsapp.com/channel/0029VaAb")
    assert is_social_link("https://t.me/sarkari")
    assert not is_social_link("https://rrb.indianrailways.gov.in/notice.pdf")


def test_big_recruitments_are_on_the_watchlist_and_labelled_links_are_found():
    from app.services.scraper_service import job_priority, watchlist_name

    assert (
        watchlist_name("RRB – Non-Technical Popular Categories – 3,548 Recruitment (Advt 06/2026)")
        == "RRB NTPC"
    )
    assert watchlist_name("RRB NTPC 10+2 UG Online Form 2026") == "RRB NTPC"
    assert watchlist_name("Notification for Common Recruitment Process for CRP- PO/MTs-XVI") == "IBPS PO"
    assert watchlist_name("SSC Combined Graduate Level Examination 2026") == "SSC CGL"
    assert watchlist_name("SSC CGL 2026 Notification") == "SSC CGL"
    assert watchlist_name("Tata Memorial Centre Gardener") is None
    assert job_priority("RRB NTPC Graduate Level Recruitment 2026") > job_priority(
        "Canara Bank 3500 Apprentice Posts"
    )

    page = """<title>RRB NTPC Graduate Recruitment 2026</title><ul>
      <li>RRB NTPC Graduate CEN 06/2026 Notification PDF: <a href="https://www.rrbapply.gov.in/assets/forms/CEN_06_2026_NTPC_G.pdf">Download PDF</a></li>
      <li>Apply Online: <a href="https://www.rrbapply.gov.in/">Click here</a></li>
      <li>Join for notifications: <a href="https://whatsapp.com/channel/x">Click here</a></li></ul>"""
    links = parse_free_job_alert_detail(page, "https://www.freejobalert.com/articles/rrb-ntpc-3068511")
    assert [lk.url for lk in links] == ["https://www.rrbapply.gov.in/assets/forms/CEN_06_2026_NTPC_G.pdf"]
