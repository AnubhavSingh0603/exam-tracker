import pytest

from app.core.config import get_settings
from app.domain.enums import ItemKind
from app.services.http_fetcher import FetchError, FetchResult
from app.services.scraper_service import classify
from app.services.telegram_service import (
    InvalidChannelError,
    collect_channel_links,
    messages_to_links,
    normalize_channel,
    parse_channel_page,
)


def page(*posts: tuple[int, str]) -> str:
    """Mimics t.me/s/<channel> markup (tgme_widget_message blocks)."""
    body = "".join(
        f"""<div class="tgme_widget_message_wrap js-widget_message_wrap">
          <div class="tgme_widget_message js-widget_message" data-post="govtjobs/{pid}">{inner}
            <div class="tgme_widget_message_footer"><a class="tgme_widget_message_date" href="https://t.me/govtjobs/{pid}">
              <time datetime="2026-10-10T09:{pid % 60:02d}:00+00:00" class="time">09:15</time></a></div>
          </div></div>"""
        for pid, inner in posts
    )
    return f'<div class="tgme_channel_info_header_title"><span dir="auto">Govt Jobs Daily</span></div>{body}'


SSC_POST = (
    101,
    """<div class="tgme_widget_message_text js-message_text" dir="auto">SSC CGL 2026 Recruitment Notification Out<br/>
   Apply: <a href="https://ssc.gov.in/api/attachment/uploads/masterData/NoticeBoards/cgl.pdf">ssc.gov.in</a>
   <a href="?q=%23ssc">#ssc</a> <a href="https://t.me/othergroup">join</a></div>""",
)
IBPS_DOC = (
    102,
    """<a class="tgme_widget_message_document_wrap" href="https://t.me/govtjobs/102">
     <div class="tgme_widget_message_document_title">IBPS_PO_Admit_Card_Notice.pdf</div></a>
   <div class="tgme_widget_message_text js-message_text">IBPS PO admit card released</div>""",
)


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("@govtjobs", "govtjobs"),
        ("govtjobs", "govtjobs"),
        ("https://t.me/s/govtjobs", "govtjobs"),
        ("t.me/govtjobs/", "govtjobs"),
        ("https://telegram.me/govtjobs", "govtjobs"),
    ],
)
def test_normalize_channel(raw, expected):
    assert normalize_channel(raw) == expected


@pytest.mark.parametrize(
    "bad", ["@ab", "https://evil.example/s/x", "name with space", "1startsdigit", "+joinchat"]
)
def test_normalize_channel_rejects(bad):
    with pytest.raises(InvalidChannelError):
        normalize_channel(bad)


def test_parse_page_extracts_text_links_documents():
    parsed = parse_channel_page(page(SSC_POST, IBPS_DOC), "govtjobs")
    assert parsed.title == "Govt Jobs Daily" and parsed.is_public_preview
    ssc, ibps = parsed.messages
    assert ssc.post_id == 101 and ssc.permalink == "https://t.me/govtjobs/101"
    # hashtag and t.me links are dropped; only the external PDF remains
    assert [u for u, _ in ssc.links] == [
        "https://ssc.gov.in/api/attachment/uploads/masterData/NoticeBoards/cgl.pdf"
    ]
    assert ssc.published_at is not None
    assert ibps.documents == ["IBPS_PO_Admit_Card_Notice.pdf"]


def test_messages_to_links_newest_first_and_classified():
    links = messages_to_links(parse_channel_page(page(SSC_POST, IBPS_DOC), "govtjobs").messages)
    assert [classify(lk)[0] for lk in links] == [ItemKind.ALERT, ItemKind.NOTIFICATION_PDF]
    assert links[0].url == "https://t.me/govtjobs/102"


class FakeFetcher:
    def __init__(self, pages: dict[str, str], final_url: str | None = None):
        self.pages, self.final_url, self.calls = pages, final_url, []

    async def get(self, url, *, max_bytes, check_robots=True):  # noqa: ARG002
        self.calls.append(url)
        return FetchResult(
            url=self.final_url or url,
            status=200,
            content_type="text/html",
            body=self.pages[url].encode(),
            encoding="utf-8",
        )


async def test_collect_stops_at_cursor_and_advances_it():
    fetcher = FakeFetcher({"https://t.me/s/govtjobs": page(SSC_POST, IBPS_DOC)})
    links, cursor = await collect_channel_links(fetcher, "https://t.me/s/govtjobs", "101", get_settings())
    assert cursor == "102"
    assert [lk.url for lk in links] == ["https://t.me/govtjobs/102"]  # 101 already seen
    assert fetcher.calls == ["https://t.me/s/govtjobs"]  # oldest on page <= cursor: no second page


async def test_private_channel_redirect_is_an_error():
    fetcher = FakeFetcher({"https://t.me/s/secret": "<html></html>"}, final_url="https://t.me/secret")
    with pytest.raises(FetchError):
        await collect_channel_links(fetcher, "https://t.me/s/secret", None, get_settings())
