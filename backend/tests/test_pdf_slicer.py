import pymupdf

from app.services.pdf_slicer import score_text, select_relevant_pages

FILLER = "General instructions to candidates. Read carefully before applying. " * 6


def make_pdf(pages: dict[int, str], total: int, *, text_layer: bool = True) -> bytes:
    """1-based page -> text; other pages get filler (or nothing, for 'scanned')."""
    doc = pymupdf.open()
    for n in range(1, total + 1):
        page = doc.new_page()
        if text_layer:
            page.insert_textbox(pymupdf.Rect(40, 40, 560, 800), pages.get(n, FILLER), fontsize=10)
        else:
            page.draw_rect(pymupdf.Rect(50, 50, 500, 700), fill=(0.9, 0.9, 0.9))
    data = doc.tobytes()
    doc.close()
    return data


def page_count(data: bytes) -> int:
    with pymupdf.open(stream=data, filetype="pdf") as d:
        return d.page_count


NOTIFICATION = {
    1: "Bharat Electronics Limited. Advertisement No. 05/2026. Recruitment of Probationary Engineers.",
    2: "Important Dates: Last date for online application 21.10.2026",
    23: "Vacancy details. Post code / UR SC ST OBC EWS / Total. No. of posts 44",
    24: "PE-ECE 20 6 3 11 4 44 (continued table rows)",
    31: "Educational Qualification: B.E./B.Tech in Electronics & Communication",
    40: "Age Limit as on 01.10.2026: 25 years. Age relaxation: SC/ST 5 years, OBC 3 years.",
}


def test_large_notification_keeps_only_relevant_pages_in_order():
    sel = select_relevant_pages(make_pdf(NOTIFICATION, 60), min_pages_to_slice=12, max_pages=24)
    assert sel.reason == "keywords" and sel.total == 60
    for must in (1, 2, 23, 24, 31, 40):
        assert must in sel.kept, must
    assert list(sel.kept) == sorted(sel.kept)
    assert len(sel.kept) < 12  # filler pages (instructions, annexures) dropped
    assert page_count(sel.data) == len(sel.kept)
    assert "of 60 pages" in sel.describe()


def test_page_budget_is_respected():
    many_hits = {n: "Vacancy table UR SC ST OBC EWS no. of posts" for n in range(3, 80)}
    sel = select_relevant_pages(make_pdf(many_hits, 80), max_pages=10)
    assert len(sel.kept) == 10 and sel.kept[:2] == (1, 2)


def test_short_pdf_sent_whole_and_unchanged():
    data = make_pdf(NOTIFICATION, 8)
    sel = select_relevant_pages(data)
    assert sel.reason == "whole" and sel.data is data and not sel.sliced


def test_scanned_pdf_falls_back_to_first_pages():
    sel = select_relevant_pages(make_pdf({}, 40, text_layer=False), max_pages=15)
    assert sel.reason == "scanned" and sel.kept == tuple(range(1, 16))


def test_scoring_signals():
    assert score_text("UR | SC | ST | OBC | EWS | Total") >= 3  # reservation table header
    assert score_text("Educational Qualification") >= 3
    assert score_text("आयु सीमा") >= 3  # Hindi: age limit
    assert score_text("Instructions for filling the OMR sheet") == 0
