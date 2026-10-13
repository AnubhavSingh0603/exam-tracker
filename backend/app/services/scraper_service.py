"""Crawl sources, detect changes, and record new links.

Pipeline for one source
-----------------------
1. ``collect_links``: fetch (httpx, Playwright fallback) and parse into ``Link``s.
2. ``fingerprint``: MD5 over the *normalised link set*, not raw HTML, so
   rotating ads, CSRF tokens and visitor counters don't look like changes.
3. If the hash changed, links never seen for this source become
   ``DiscoveredItem``s, classified by ``classify``:
     NOTIFICATION_PDF -> queued for Gemini (discovery_pipeline.ingest_pending_pdfs)
     DETAIL_PAGE      -> aggregator page to open later (discovery_pipeline.follow_detail_pages)
     ALERT            -> admit card / exam date / postponed / corrigendum
4. First crawl of a source records everything as BASELINE except the newest
   ``seed_backfill_per_source`` actionable items, so adding a source never
   floods the Gemini free tier.
5. A job link whose "Last Date" (printed beside it on aggregator lists) has
   passed is SKIPPED: reading it would spend a Gemini request on a closed job.

Parsers were written against the live markup of each site in Oct 2026. They
fall back to the generic DOM parser when their selectors find nothing.
"""

from __future__ import annotations

import hashlib
import json
import logging
import random
import re
import uuid
from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from urllib.parse import urljoin, urlsplit, urlunsplit
from zoneinfo import ZoneInfo

from bs4 import BeautifulSoup, Tag
from dateutil import parser as dateparser
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.domain.enums import ItemKind, ItemStatus, ParserKey
from app.models import DiscoveredItem, Source
from app.services.http_fetcher import Fetcher
from app.services.js_renderer import looks_js_rendered, render_page

log = logging.getLogger(__name__)

# =============================================================================
# Link model + keyword engine
# =============================================================================


@dataclass(frozen=True, slots=True)
class Link:
    url: str
    title: str
    context: str = ""  # surrounding row/list text; carries dates, "Last Date", labels
    published_at: datetime | None = None
    pdf_hint: bool = False  # parser knows it's a document even without ".pdf"
    detail_page: bool = False  # aggregator page that must be opened to find the PDF


# Flag -> phrases, matched as whole words/phrases (so "extension of" can't match
# "Extension Officer"). Inflections are listed explicitly instead of using stems.
ALERT_KEYWORDS: dict[str, tuple[str, ...]] = {
    "admit_card": ("admit card", "admit cards", "e-admit card", "call letter", "call letters", "hall ticket"),
    "exam_date": (
        "exam date",
        "exam dates",
        "exam schedule",
        "examination schedule",
        "exam city",
        "date of exam",
        "date of examination",
    ),
    "postponed": (
        "postpone",
        "postponed",
        "postponement",
        "rescheduled",
        "re-scheduled",
        "deferred",
        "cancelled",
        "cancellation",
    ),
    "corrigendum": ("corrigendum", "addendum", "erratum"),
    "date_extended": (
        "date extended",
        "extension of last date",
        "last date extended",
        "extended till",
        "extended upto",
        "extended up to",
    ),
}
RECRUITMENT_HINTS = (
    "recruitment",
    "notification",
    "advertisement",
    "advt",
    "vacanc",
    "online form",
    "apply online",
    "engagement",
    "employment notice",
    "detailed notice",
    "rozgar",
)
NOISE_HINTS = (
    "tentative vacanc",
    "result",
    "answer key",
    "marks",
    "cut off",
    "cutoff",
    "cut-off",
    "merit list",
    "response sheet",
    "syllabus",
    "debarred",
    "score card",
    "scorecard",
    "tender",
    "rti",
    "annual report",
)


_ALERT_PATTERNS = {
    flag: re.compile(r"\b(?:" + "|".join(re.escape(p) for p in phrases) + r")\b", re.IGNORECASE)
    for flag, phrases in ALERT_KEYWORDS.items()
}


def flag_keywords(text: str) -> list[str]:
    return [flag for flag, pattern in _ALERT_PATTERNS.items() if pattern.search(text)]


def _looks_like_pdf_url(url: str) -> bool:
    path = urlsplit(url).path.lower()
    return path.endswith(".pdf") or "/pdf/" in path


def classify(link: Link) -> tuple[ItemKind, list[str]]:
    text = f"{link.title} {link.context}".lower()
    flags = flag_keywords(text)
    if flags:
        return ItemKind.ALERT, flags
    recruitment = any(h in text for h in RECRUITMENT_HINTS)
    noise = any(h in text for h in NOISE_HINTS)
    if link.detail_page:
        return (ItemKind.DETAIL_PAGE if recruitment and not noise else ItemKind.OTHER), flags
    if (link.pdf_hint or _looks_like_pdf_url(link.url)) and recruitment and not noise:
        return ItemKind.NOTIFICATION_PDF, flags
    return ItemKind.OTHER, flags


# =============================================================================
# Normalisation + fingerprint
# =============================================================================

_WS = re.compile(r"\s+")
_TRACKING_PARAMS = re.compile(r"^(utm_|fbclid|gclid|ref$|amp$)")


def clean_text(text: str, limit: int = 500) -> str:
    return _WS.sub(" ", text).strip()[:limit]


def canonical_url(url: str) -> str:
    """Drop fragments and tracking params so the same link isn't 'new' twice."""
    parts = urlsplit(url.strip())
    query = "&".join(
        kv for kv in parts.query.split("&") if kv and not _TRACKING_PARAMS.match(kv.split("=", 1)[0])
    )
    return urlunsplit((parts.scheme.lower(), parts.netloc.lower(), parts.path or "/", query, ""))


def fingerprint(links: Iterable[Link]) -> str:
    lines = sorted({f"{lk.url}|{lk.title.lower()}" for lk in links})
    return hashlib.md5("\n".join(lines).encode("utf-8"), usedforsecurity=False).hexdigest()


# =============================================================================
# Parsers
# =============================================================================

_SKIP_HREF = ("#", "mailto:", "tel:", "javascript:", "whatsapp:")
_CHROME_TAGS = ("nav", "header", "footer")


def _soup(html: bytes | str) -> BeautifulSoup:
    return BeautifulSoup(html, "lxml")


def _context_for(a: Tag) -> str:
    container = a.find_parent(["tr", "li"]) or a.parent
    return clean_text(container.get_text(" ", strip=True)) if container else ""


def _anchor_links(scope: Tag | BeautifulSoup, base_url: str, *, skip_chrome: bool = True) -> list[Link]:
    seen: dict[str, Link] = {}
    for a in scope.find_all("a", href=True):
        href = str(a["href"]).strip()
        if not href or href.lower().startswith(_SKIP_HREF):
            continue
        if skip_chrome and a.find_parent(_CHROME_TAGS) is not None:
            continue
        url = canonical_url(urljoin(base_url, href))
        if not url.startswith(("http://", "https://")):
            continue
        title = clean_text(a.get_text(" ", strip=True), 300) or clean_text(str(a.get("title", "")), 300)
        context = _context_for(a)
        if not title:
            title = context[:300]
        prev = seen.get(url)
        if prev is None or len(title) > len(prev.title):
            seen[url] = Link(url=url, title=title, context=context)
    return list(seen.values())


def parse_generic(html: bytes | str, base_url: str) -> list[Link]:
    """Any career page: every content link with its row/list context.
    Table rows are covered because the row text becomes the link context."""
    return _anchor_links(_soup(html), base_url)


# sarkariresult.com, and the unofficial copy sarkariresult.com.cm, which uses the same
# detail-page tables and is reachable from GitHub's US runners (the original returns 403).
SARKARI_RESULT_DOMAINS = ("sarkariresult.com", "sarkariresult.com.cm")


def _is_sarkari_result(netloc: str) -> bool:
    return netloc.endswith(SARKARI_RESULT_DOMAINS)


def parse_sarkari_result_list(html: bytes | str, base_url: str) -> list[Link]:
    soup = _soup(html)
    links: list[Link] = []
    for li in soup.select("ul.wp-block-list li, ul.sarkari-quick-list li, ul.latest-posts-last-date li"):
        a = li.find("a", href=True)
        if a is None:
            continue
        url = canonical_url(urljoin(base_url, str(a["href"])))
        if _is_sarkari_result(urlsplit(url).netloc):
            text = clean_text(li.get_text(" ", strip=True), 300)
            links.append(Link(url=url, title=text, context=text, detail_page=True))
    return links or parse_generic(html, base_url)


def parse_sarkari_result_detail(html: bytes | str, base_url: str) -> list[Link]:
    """Detail pages have a 'Useful Important Links' table: 'Download Notification | Click Here'.
    The PDF is often hosted under /wp-content/uploads/ with no .pdf extension."""
    soup = _soup(html)
    page_title = clean_text(soup.title.get_text() if soup.title else "", 200)
    out: list[Link] = []
    for tr in soup.find_all("tr"):
        if tr.find("tr") is not None or len(tr.find_all(["td", "th"], recursive=False)) > 3:
            continue  # layout tables wrap the whole page; we want the 2-cell link rows
        label = clean_text(tr.get_text(" ", strip=True), 200)
        if "notification" not in label.lower() or len(label) > 120:
            continue
        for a in tr.find_all("a", href=True):
            url = canonical_url(urljoin(base_url, str(a["href"])))
            parts = urlsplit(url)
            own_site = _is_sarkari_result(parts.netloc)
            if own_site and "/wp-content/uploads/" not in parts.path and not _looks_like_pdf_url(url):
                continue  # links back into SarkariResult itself (home, categories)
            out.append(Link(url=url, title=page_title or label, context=label, pdf_hint=True))
    return out


def parse_free_job_alert_list(html: bytes | str, base_url: str) -> list[Link]:
    """Rows: Post Date | Board | Post Name | Qualification | Advt No | Last Date | Get Details."""
    soup = _soup(html)
    links: list[Link] = []
    for tr in soup.select("table.lattbl tr"):
        cells = [clean_text(td.get_text(" ", strip=True), 120) for td in tr.find_all("td")]
        a = tr.find("a", href=True)
        if len(cells) < 6 or a is None:
            continue
        posted, board, post, _qual, advt, last_date = cells[:6]
        title = f"{board} – {post} Recruitment" + (f" (Advt {advt})" if advt.strip("– ") else "")
        published = _parse_ddmmyyyy(posted)
        links.append(
            Link(
                url=canonical_url(urljoin(base_url, str(a["href"]))),
                title=clean_text(title, 300),
                context=f"Last date {last_date}",
                published_at=published,
                detail_page=True,
            )
        )
    return links or parse_generic(html, base_url)


def parse_free_job_alert_detail(html: bytes | str, base_url: str) -> list[Link]:
    """'Download Official Notification' links straight to the board's own PDF."""
    soup = _soup(html)
    page_title = clean_text(soup.title.get_text() if soup.title else "", 200)
    out: list[Link] = []
    for a in soup.find_all("a", href=True):
        text = clean_text(a.get_text(" ", strip=True), 120).lower()
        url = canonical_url(urljoin(base_url, str(a["href"])))
        if "notification" in text and not urlsplit(url).netloc.endswith("freejobalert.com"):
            out.append(Link(url=url, title=page_title or text, context=text, pdf_hint=True))
    return out


SSC_API_BASE = "https://ssc.gov.in/api/attachment/"


def parse_ssc_api(body: bytes | str, base_url: str) -> list[Link]:  # noqa: ARG001
    """ssc.gov.in is a React SPA; its notice board is served by a public JSON API."""
    data = json.loads(body)
    out: list[Link] = []
    for rec in data.get("data") or []:
        headline = clean_text(str(rec.get("headline") or ""), 300)
        published = _parse_iso(rec.get("createdAt"))
        for att in rec.get("attachments") or []:
            path = str(att.get("path") or "").replace("\\", "/").lstrip("/")
            if not path:
                continue
            out.append(
                Link(
                    url=SSC_API_BASE + path,
                    title=headline,
                    context=headline,
                    published_at=published,
                    pdf_hint=att.get("type") == "application/pdf",
                )
            )
    return out


def _parse_ddmmyyyy(text: str) -> datetime | None:
    m = re.search(r"(\d{1,2})[/-](\d{1,2})[/-](\d{4})", text)
    if not m:
        return None
    try:
        return datetime(int(m[3]), int(m[2]), int(m[1]), tzinfo=UTC)
    except ValueError:
        return None


def _parse_iso(value: object) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


# "Last Date: 25 November 2026" (SarkariResult), "Last date 25/11/2026" (FreeJobAlert),
# "Last Date Extended till 30-11-2026".
_LAST_DATE = re.compile(
    r"\blast\s+date\b\D{0,40}?"
    r"(\d{1,2}[./-]\d{1,2}[./-]\d{4}|\d{1,2}(?:st|nd|rd|th)?\s+[a-z]{3,9}\.?,?\s+\d{4})",
    re.IGNORECASE,
)


def closing_date(text: str) -> date | None:
    """The 'Last Date' an aggregator prints beside a job link, if any."""
    m = _LAST_DATE.search(text)
    if m is None:
        return None
    try:
        d = dateparser.parse(m[1], dayfirst=True).date()
    except (ValueError, OverflowError):
        return None
    return d if 2000 <= d.year <= 2100 else None


def closed_note(text: str, today: date) -> str | None:
    """Why a job link is skipped unread: its 'Last Date' is before ``today``."""
    closes = closing_date(text)
    if closes is None or closes >= today:
        return None
    return f"Closed on {closes:%d %b %Y} before it was read"


def local_today(settings: Settings, now: datetime | None = None) -> date:
    return (now or datetime.now(UTC)).astimezone(ZoneInfo(settings.timezone)).date()


LIST_PARSERS = {
    ParserKey.GENERIC: parse_generic,
    ParserKey.SARKARI_RESULT: parse_sarkari_result_list,
    ParserKey.FREE_JOB_ALERT: parse_free_job_alert_list,
    ParserKey.SSC_API: parse_ssc_api,
}
DETAIL_PARSERS = {
    ParserKey.SARKARI_RESULT: parse_sarkari_result_detail,
    ParserKey.FREE_JOB_ALERT: parse_free_job_alert_detail,
}


# =============================================================================
# Crawler
# =============================================================================


@dataclass
class CrawlOutcome:
    source_id: str
    changed: bool = False
    new_items: int = 0
    queued: int = 0
    alerts: int = 0
    error: str | None = None
    flags: list[str] = field(default_factory=list)


def next_check_time(now: datetime, settings: Settings, *, failures: int = 0) -> datetime:
    base = timedelta(hours=settings.crawl_interval_hours)
    if failures:
        base = min(base * (2 ** min(failures, 4)), timedelta(hours=24))
    jitter = timedelta(minutes=random.uniform(-settings.crawl_jitter_minutes, settings.crawl_jitter_minutes))
    return now + max(base + jitter, timedelta(minutes=30))


class SourceCrawler:
    def __init__(self, fetcher: Fetcher, settings: Settings | None = None) -> None:
        self.fetcher = fetcher
        self.settings = settings or get_settings()

    async def collect_links(self, source: Source) -> list[Link]:
        if source.parser is ParserKey.TELEGRAM:
            from app.services.telegram_service import collect_channel_links

            links, cursor = await collect_channel_links(
                self.fetcher, source.url, source.cursor, self.settings
            )
            if cursor:
                source.cursor = cursor
            return links

        parse = LIST_PARSERS.get(source.parser, parse_generic)
        res = await self.fetcher.get(source.url, max_bytes=self.settings.max_page_bytes)
        links = parse(res.body, res.url)
        if (
            self.settings.playwright_enabled
            and source.parser is ParserKey.GENERIC
            and (source.render_js or looks_js_rendered(res.text, len(links)))
        ):
            html = await render_page(source.url, user_agent=self.fetcher.user_agent)
            links = parse_generic(html, source.url)
        return links

    async def crawl(
        self, session: AsyncSession, source: Source, *, now: datetime | None = None
    ) -> CrawlOutcome:
        now = now or datetime.now(UTC)
        outcome = CrawlOutcome(source_id=str(source.id))
        source.last_checked_at = now
        try:
            links = await self.collect_links(source)
        except Exception as exc:  # noqa: BLE001 - one broken source must not stop the tick
            source.consecutive_failures += 1
            source.last_error = str(exc)[:1000]
            source.next_check_at = next_check_time(now, self.settings, failures=source.consecutive_failures)
            await session.commit()
            outcome.error = source.last_error
            log.warning("Crawl failed for %s: %s", source.name, exc)
            return outcome

        source.consecutive_failures = 0
        source.last_error = None
        source.next_check_at = next_check_time(now, self.settings)

        digest = fingerprint(links)
        first_crawl = source.content_hash is None
        if digest == source.content_hash:
            await session.commit()
            return outcome

        outcome.changed = True
        source.content_hash = digest
        source.last_changed_at = now
        rows = await self._new_item_rows(
            session, source, links, first_crawl=first_crawl, today=local_today(self.settings, now)
        )
        if rows:
            await session.execute(
                pg_insert(DiscoveredItem)
                .values(rows)
                .on_conflict_do_nothing(index_elements=["source_id", "url"])
            )
        await session.commit()

        outcome.new_items = len(rows)
        outcome.queued = sum(1 for r in rows if r["status"] == ItemStatus.PENDING)
        outcome.alerts = sum(
            1 for r in rows if r["kind"] == ItemKind.ALERT and r["status"] != ItemStatus.BASELINE
        )
        outcome.flags = sorted({f for r in rows if r["status"] != ItemStatus.BASELINE for f in r["keywords"]})
        log.info(
            "Crawled %s: %d new (%d queued, %d alerts)%s",
            source.name,
            outcome.new_items,
            outcome.queued,
            outcome.alerts,
            " [baseline]" if first_crawl else "",
        )
        return outcome

    async def _new_item_rows(
        self, session: AsyncSession, source: Source, links: list[Link], *, first_crawl: bool, today: date
    ) -> list[dict[str, object]]:
        if not links:
            return []
        known = set(
            await session.scalars(
                select(DiscoveredItem.url).where(
                    DiscoveredItem.source_id == source.id,
                    DiscoveredItem.url.in_([lk.url for lk in links]),
                )
            )
        )
        backfill = self.settings.seed_backfill_per_source
        rows: list[dict[str, object]] = []
        actionable_seen = 0
        for link in links:  # page order: newest first on every source we parse
            if link.url in known:
                continue
            known.add(link.url)
            kind, flags = classify(link)
            actionable = kind in (ItemKind.NOTIFICATION_PDF, ItemKind.DETAIL_PAGE)
            closed = closed_note(f"{link.title} {link.context}", today) if actionable else None
            if kind is ItemKind.OTHER:
                status = ItemStatus.SKIPPED
            elif closed:
                status, actionable = ItemStatus.SKIPPED, False  # not worth a backfill slot either
            elif first_crawl and not (actionable and actionable_seen < backfill):
                status = ItemStatus.BASELINE
            elif kind is ItemKind.ALERT:
                status = ItemStatus.DONE  # recorded; surfaced via /sources/alerts
            else:
                status = ItemStatus.PENDING
            actionable_seen += actionable
            rows.append(
                {
                    "id": uuid.uuid4(),
                    "attempts": 0,
                    "source_id": source.id,
                    "url": link.url[:2000],
                    "title": (link.title or link.url)[:500],
                    "kind": kind,
                    "status": status,
                    "keywords": flags,
                    "published_at": link.published_at,
                    "error": closed,
                }
            )
        return rows
