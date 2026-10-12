"""Send Gemini only the pages that matter.

Recruitment notifications are often 40–120 pages: bilingual duplicates, annexures,
application-form facsimiles, syllabus. The data we extract (dates, posts, vacancy
matrix, qualifications, age rules) usually sits on a handful of them. Slicing
cuts tokens (free-tier quota), latency and timeouts on huge PDFs.

Strategy
  * PDFs with <= PDF_SLICE_MIN_PAGES pages are sent whole.
  * Always keep the first pages (title, advertisement no., important dates).
  * Score every page's text (English + Hindi keywords), plus TOC/bookmark titles.
  * Keep hit pages and the page after a strong hit (tables spill over).
  * Cap at PDF_SLICE_MAX_PAGES, highest scores first, original order preserved.
  * Scanned PDFs (no text layer) can't be scored: send the first N pages.

PyMuPDF is AGPL-3.0 licensed. Fine for a self-hosted backend whose source you
publish; if you'd rather avoid AGPL, pypdf (BSD) can replace the two calls used here.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

import pymupdf

log = logging.getLogger(__name__)

# (pattern, weight). Patterns are matched against lower-cased page text.
_KEYWORDS: tuple[tuple[str, int], ...] = (
    # vacancy matrix
    (r"\bvacanc(?:y|ies)\b", 3),
    (r"\bno\.? of posts\b|\bnumber of posts\b|\btotal posts\b", 3),
    (r"category[- ]wise", 2),
    # qualifications / eligibility
    (r"\beducational qualification", 3),
    (r"\bessential qualification", 3),
    (r"\beligibility\b", 2),
    (r"\bqualification\b", 1),
    # age rules
    (r"\bage limit\b|\bupper age\b|\bmaximum age\b", 3),
    (r"\bage relaxation\b|\brelaxation in (?:upper )?age\b", 3),
    (r"\bas on\b.{0,20}\d{4}", 1),
    # dates / application
    (r"\bimportant dates\b|\blast date\b|\bclosing date\b", 2),
    (r"\bapplication fee\b", 1),
    # Hindi (bilingual notifications)
    (r"रिक्ति|रिक्तियों|पदों की संख्या", 3),
    (r"शैक्षणिक योग्यता|शैक्षिक योग्यता|पात्रता", 3),
    (r"आयु सीमा|आयु में छूट", 3),
    (r"अंतिम तिथि|महत्वपूर्ण तिथि", 2),
)
_COMPILED = tuple((re.compile(p), w) for p, w in _KEYWORDS)
_RESERVATION_COLUMNS = ("obc", "ews", "sc", "st")
STRONG_HIT = 5


@dataclass(frozen=True, slots=True)
class PageSelection:
    data: bytes
    kept: tuple[int, ...]  # 1-based page numbers sent to Gemini
    total: int
    reason: str  # "whole" | "keywords" | "scanned" | "no-hits"

    @property
    def sliced(self) -> bool:
        return len(self.kept) < self.total

    def describe(self) -> str:
        return f"Gemini read {len(self.kept)} of {self.total} pages ({_ranges(self.kept)}; {self.reason})"


def _ranges(pages: tuple[int, ...]) -> str:
    out: list[str] = []
    start = prev = None
    for p in pages:
        if start is None:
            start = prev = p
        elif p == prev + 1:
            prev = p
        else:
            out.append(f"{start}" if start == prev else f"{start}-{prev}")
            start = prev = p
    if start is not None:
        out.append(f"{start}" if start == prev else f"{start}-{prev}")
    return ", ".join(out)


def score_text(text: str) -> int:
    low = text.lower()
    score = sum(w for pat, w in _COMPILED if pat.search(low))
    # A table header listing several reservation categories is a strong vacancy-matrix signal.
    cols = sum(1 for c in _RESERVATION_COLUMNS if re.search(rf"\b{c}\b", low))
    if cols >= 3:
        score += 3
    return score


def select_relevant_pages(
    data: bytes,
    *,
    min_pages_to_slice: int = 12,
    max_pages: int = 24,
    always_first: int = 2,
) -> PageSelection:
    with pymupdf.open(stream=data, filetype="pdf") as doc:
        total = doc.page_count
        if total <= min_pages_to_slice:
            return PageSelection(data, tuple(range(1, total + 1)), total, "whole")

        texts = [page.get_text("text") for page in doc]
        with_text = sum(1 for t in texts if len(t.strip()) > 80)
        if with_text < total * 0.3:
            keep = list(range(min(max_pages, total)))
            return _subset(doc, keep, total, "scanned")

        scores = [score_text(t) for t in texts]
        for _level, title, page_no in doc.get_toc(simple=True):
            if 1 <= page_no <= total and score_text(title) > 0:
                scores[page_no - 1] += 2  # bookmarks like "Educational Qualification"

        if not any(scores):
            return _subset(doc, list(range(min(max_pages, total))), total, "no-hits")

        first = set(range(min(always_first, total)))
        candidates: dict[int, int] = {}
        for i, s in enumerate(scores):
            if s > 0:
                candidates[i] = max(candidates.get(i, 0), s)
                if s >= STRONG_HIT and i + 1 < total:
                    candidates.setdefault(i + 1, 1)  # continuation of a table
        budget = max_pages - len(first)
        ranked = sorted((i for i in candidates if i not in first), key=lambda i: (-candidates[i], i))
        keep = sorted(first | set(ranked[: max(budget, 0)]))
        return _subset(doc, keep, total, "keywords")


def _subset(doc: pymupdf.Document, keep: list[int], total: int, reason: str) -> PageSelection:
    # select() keeps pages inside the original document, so fonts/images shared
    # across pages stay shared. Copying pages into a new PDF one by one duplicates
    # them, and real notifications came out 3-4x LARGER despite having fewer pages.
    doc.select(keep)
    data = doc.tobytes(garbage=4, deflate=True, deflate_images=True, deflate_fonts=True, use_objstms=1)
    selection = PageSelection(data, tuple(i + 1 for i in keep), total, reason)
    log.info(selection.describe())
    return selection
