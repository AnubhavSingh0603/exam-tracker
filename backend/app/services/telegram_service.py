"""Public Telegram channel reader via the web preview at https://t.me/s/<channel>.

No bot token or account needed, but only *public* channels with the web
preview enabled work. What we can get from the preview:
  * message text, timestamp and permalink
  * every hyperlink in the text (often the board's official PDF URL)
  * attached document *titles* — the preview does not expose file downloads.
    Those become alerts linking to the post; fetching the file itself would
    need MTProto (e.g. Telethon with a user session), deliberately out of scope.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from urllib.parse import urljoin, urlsplit

from bs4 import BeautifulSoup

from app.core.config import Settings
from app.services.http_fetcher import Fetcher, FetchError
from app.services.scraper_service import Link, canonical_url, clean_text

PREVIEW_BASE = "https://t.me/s/"
_HANDLE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]{3,31}$")
_URL_FORMS = re.compile(r"^(?:https?://)?(?:www\.)?(?:t\.me|telegram\.me)/(?:s/)?([A-Za-z0-9_]+)/?$", re.I)


class InvalidChannelError(ValueError):
    pass


def normalize_channel(raw: str) -> str:
    """Accepts '@name', 'name', 't.me/name', 'https://t.me/s/name'. Returns 'name'."""
    value = raw.strip()
    m = _URL_FORMS.match(value)
    name = m[1] if m else value.lstrip("@")
    if not _HANDLE_RE.match(name):
        raise InvalidChannelError("Not a valid public channel username (5–32 letters, digits, _)")
    return name


def channel_preview_url(channel: str, before: int | None = None) -> str:
    return f"{PREVIEW_BASE}{channel}" + (f"?before={before}" if before else "")


@dataclass
class TelegramMessage:
    post_id: int
    permalink: str
    text: str
    published_at: datetime | None
    links: list[tuple[str, str]] = field(default_factory=list)  # (url, anchor text)
    documents: list[str] = field(default_factory=list)  # attachment titles


@dataclass
class ChannelPage:
    title: str | None
    messages: list[TelegramMessage]

    @property
    def is_public_preview(self) -> bool:
        return self.title is not None or bool(self.messages)


def parse_channel_page(html: bytes | str, channel: str) -> ChannelPage:
    soup = BeautifulSoup(html, "lxml")
    title_el = soup.select_one(".tgme_channel_info_header_title")
    messages: list[TelegramMessage] = []
    for msg in soup.select("div.tgme_widget_message[data-post]"):
        post = str(msg.get("data-post", ""))
        try:
            post_id = int(post.rsplit("/", 1)[1])
        except (IndexError, ValueError):
            continue
        text_el = msg.select_one(".tgme_widget_message_text")
        text = clean_text(text_el.get_text("\n", strip=True), 2000) if text_el else ""
        time_el = msg.select_one(".tgme_widget_message_date time[datetime]")
        published = None
        if time_el is not None:
            try:
                published = datetime.fromisoformat(str(time_el["datetime"]))
            except ValueError:
                published = None
        links: list[tuple[str, str]] = []
        if text_el is not None:
            for a in text_el.find_all("a", href=True):
                href = urljoin("https://t.me/", str(a["href"]))
                host = urlsplit(href).netloc.lower()
                if host in ("t.me", "telegram.me") or not href.startswith(("http://", "https://")):
                    continue  # hashtags, mentions, internal links
                links.append((canonical_url(href), clean_text(a.get_text(" ", strip=True), 200)))
        documents = [
            clean_text(d.get_text(" ", strip=True), 200)
            for d in msg.select(".tgme_widget_message_document_title")
        ]
        messages.append(
            TelegramMessage(
                post_id=post_id,
                permalink=f"https://t.me/{channel}/{post_id}",
                text=text,
                published_at=published,
                links=links,
                documents=[d for d in documents if d],
            )
        )
    title = clean_text(title_el.get_text(" ", strip=True), 200) if title_el else None
    return ChannelPage(title=title, messages=messages)


def messages_to_links(messages: list[TelegramMessage]) -> list[Link]:
    """Newest first, matching the order the crawler expects."""
    out: list[Link] = []
    for m in sorted(messages, key=lambda x: x.post_id, reverse=True):
        headline = (m.text.split("\n", 1)[0] if m.text else "")[:300]
        for url, anchor in m.links:
            out.append(
                Link(
                    url=url,
                    title=headline or anchor or url,
                    context=m.text[:500],
                    published_at=m.published_at,
                )
            )
        for doc in m.documents:
            # Not downloadable from the preview: record against the post permalink.
            out.append(
                Link(
                    url=m.permalink,
                    title=f"📎 {doc} — {headline}"[:300],
                    context=m.text[:500],
                    published_at=m.published_at,
                )
            )
        if not m.links and not m.documents and m.text:
            out.append(
                Link(url=m.permalink, title=headline, context=m.text[:500], published_at=m.published_at)
            )
    return out


async def fetch_channel_page(
    fetcher: Fetcher, channel: str, *, before: int | None, max_bytes: int
) -> ChannelPage:
    res = await fetcher.get(channel_preview_url(channel, before), max_bytes=max_bytes)
    # Private/nonexistent channels redirect to t.me/<name> without the /s/ preview.
    if "/s/" not in urlsplit(res.url).path:
        raise FetchError("Channel is private or has no public web preview")
    return parse_channel_page(res.body, channel)


async def collect_channel_links(
    fetcher: Fetcher, source_url: str, cursor: str | None, settings: Settings
) -> tuple[list[Link], str | None]:
    """Reads up to ``telegram_pages_per_crawl`` pages, stopping once we reach the
    previously seen post. Returns (links, new_cursor)."""
    channel = normalize_channel(source_url)
    last_seen = int(cursor) if cursor and cursor.isdigit() else 0
    collected: list[TelegramMessage] = []
    before: int | None = None
    for _ in range(max(1, settings.telegram_pages_per_crawl)):
        page = await fetch_channel_page(fetcher, channel, before=before, max_bytes=settings.max_page_bytes)
        if not page.messages:
            break
        collected.extend(m for m in page.messages if m.post_id > last_seen)
        oldest = min(m.post_id for m in page.messages)
        if oldest <= last_seen or oldest <= 1:
            break
        before = oldest
    newest = max((m.post_id for m in collected), default=last_seen)
    return messages_to_links(collected), (str(newest) if newest else cursor)
