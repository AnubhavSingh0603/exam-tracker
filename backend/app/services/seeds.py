"""Built-in sources, crawled for everyone out of the box.

Verified against live sites in Oct 2026:
  * SarkariResult: /latestjob/ and /admitcard/ are long <ul class="wp-block-list"> lists
    linking to detail pages whose "Download Notification" row holds the PDF.
  * FreeJobAlert: <table class="lattbl"> rows -> article pages with
    "Download Official Notification" pointing at the board's own PDF.
  * SSC: ssc.gov.in is a React SPA; the notice board comes from a public JSON API.
  * UPSC: the home page's "What's New" block links PDFs directly
    (deep links like /whats-new redirect to the home page for bots).
  * IBPS: home page links notices/PDFs directly.
Both aggregators' robots.txt allow crawling of these pages.
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.enums import ParserKey, SourceKind
from app.models import Source


@dataclass(frozen=True)
class Seed:
    name: str
    url: str
    parser: ParserKey
    render_js: bool = False


SSC_NOTICE_BOARD_API = (
    "https://ssc.gov.in/api/general-website/portal/notice-boards?page=1&limit=25"
    "&contentType=notice-boards&key=createdAt&order=DESC&isAttachment=true&language=english"
    "&attributes=id,headline,examId,contentType,redirectUrl,startDate,endDate,language,createdAt"
)

SEEDS: tuple[Seed, ...] = (
    Seed("SarkariResult · Latest Jobs", "https://www.sarkariresult.com/latestjob/", ParserKey.SARKARI_RESULT),
    Seed("SarkariResult · Admit Cards", "https://www.sarkariresult.com/admitcard/", ParserKey.SARKARI_RESULT),
    Seed(
        "FreeJobAlert · Latest Notifications",
        "https://www.freejobalert.com/latest-notifications/",
        ParserKey.FREE_JOB_ALERT,
    ),
    # Unofficial copy of SarkariResult (its disclaimer: "a private website… not affiliated
    # with any government institution"). Used only to *find* links: jobs are read from the
    # official notification PDF it points to; notices link to its page for that exam.
    *(
        Seed(
            f"SarkariResult.com.cm (unofficial) · {label}",
            f"https://sarkariresult.com.cm/{path}/",
            ParserKey.SARKARI_RESULT,
        )
        for label, path in (("Latest Jobs", "latest-jobs"),)
    ),
    # Its Admit Card / Answer Key / Result sections through the site's public WordPress
    # API (categories 3, 4, 6): the section pages' markup lists no posts we can read.
    # "section=" is ignored by WordPress and tells the pipeline which notices these are.
    *(
        Seed(
            f"SarkariResult.com.cm (unofficial) · {label}",
            f"https://sarkariresult.com.cm/wp-json/wp/v2/posts?categories={category}&per_page=50"
            f"&_fields=id,date,modified,link,title&section={section}",
            ParserKey.WORDPRESS_POSTS,
        )
        for label, category, section in (
            ("Admit Cards", 3, "admit-card"),
            ("Answer Keys", 4, "answer-key"),
            ("Results", 6, "result"),
        )
    ),
    Seed("SSC · Notice Board", SSC_NOTICE_BOARD_API, ParserKey.SSC_API),
    Seed("UPSC · What's New", "https://upsc.gov.in/", ParserKey.GENERIC),
    Seed("IBPS · Latest Updates", "https://www.ibps.in/", ParserKey.GENERIC),
)


# Seeds replaced by better ones: switched off (kept for their history).
RETIRED_SEED_URLS = frozenset(
    f"https://sarkariresult.com.cm/{path}/" for path in ("admit-card", "answer-key", "result")
)


async def ensure_seed_sources(session: AsyncSession) -> int:
    """Insert missing seeds; never re-enables a seed the owner disabled."""
    for retired in await session.scalars(
        select(Source).where(Source.kind == SourceKind.SEED, Source.url.in_(RETIRED_SEED_URLS))
    ):
        retired.enabled = False
    existing = set(await session.scalars(select(Source.url).where(Source.kind == SourceKind.SEED)))
    added = 0
    for seed in SEEDS:
        if seed.url in existing:
            continue
        session.add(
            Source(
                kind=SourceKind.SEED,
                parser=seed.parser,
                name=seed.name,
                url=seed.url,
                render_js=seed.render_js,
            )
        )
        added += 1
    await session.commit()
    return added
