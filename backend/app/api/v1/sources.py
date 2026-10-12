import uuid
from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from sqlalchemy import func, or_, select

from app.api.deps import CurrentUser, SessionDep
from app.core.config import get_settings
from app.domain.enums import ItemKind, ItemStatus, ParserKey, SourceKind
from app.models import DiscoveredItem, Source, User
from app.schemas.source import AlertOut, CustomUrlIn, SourceCreated, SourceOut, SourcePreview, TelegramIn
from app.services.http_fetcher import BlockedURLError, Fetcher, FetchError, RobotsDisallowedError
from app.services.scraper_service import canonical_url, classify, parse_generic
from app.services.telegram_service import (
    InvalidChannelError,
    channel_preview_url,
    fetch_channel_page,
    messages_to_links,
    normalize_channel,
)

router = APIRouter(prefix="/sources", tags=["sources"])


def get_fetcher(request: Request) -> Fetcher:
    return request.app.state.fetcher


FetcherDep = Annotated[Fetcher, Depends(get_fetcher)]


def _fetch_error(exc: FetchError) -> HTTPException:
    if isinstance(exc, BlockedURLError):
        msg = "That address can't be tracked (private or non-web address)."
    elif isinstance(exc, RobotsDisallowedError):
        msg = "The site's robots.txt asks crawlers not to read this page."
    else:
        msg = f"Couldn't load it: {exc}"
    return HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, msg)


def _out(source: Source, user: User) -> SourceOut:
    out = SourceOut.model_validate(source)
    out.is_mine = source.owner_id == user.id
    return out


def _preview(links: list) -> SourcePreview:  # noqa: ANN001
    kinds = [(lk, *classify(lk)) for lk in links]
    candidates = [lk for lk, kind, _ in kinds if kind in (ItemKind.NOTIFICATION_PDF, ItemKind.DETAIL_PAGE)]
    alerts = [lk for lk, kind, _ in kinds if kind is ItemKind.ALERT]
    return SourcePreview(
        links_found=len(links),
        notification_candidates=len(candidates),
        alerts=len(alerts),
        sample=[lk.title for lk in (candidates + alerts)[:5]],
    )


async def _check_quota(session: SessionDep, user: User) -> None:
    count = await session.scalar(select(func.count()).select_from(Source).where(Source.owner_id == user.id))
    if (count or 0) >= get_settings().max_custom_sources_per_user:
        raise HTTPException(status.HTTP_409_CONFLICT, "Source limit reached; delete one first")


async def _existing(session: SessionDep, kind: SourceKind, url: str) -> Source | None:
    return await session.scalar(select(Source).where(Source.kind == kind, Source.url == url))


@router.post("/custom-url", response_model=SourceCreated, status_code=status.HTTP_201_CREATED)
async def add_custom_url(
    body: CustomUrlIn, user: CurrentUser, session: SessionDep, fetcher: FetcherDep, response: Response
) -> SourceCreated:
    """Track any career page. We fetch it once now to validate and preview what it would find."""
    url = canonical_url(str(body.url))
    if existing := await _existing(session, SourceKind.CUSTOM_URL, url):
        response.status_code = status.HTTP_200_OK
        return SourceCreated(source=_out(existing, user), already_tracked=True, preview=None)
    await _check_quota(session, user)

    settings = get_settings()
    try:
        res = await fetcher.get(url, max_bytes=settings.max_page_bytes)
    except FetchError as exc:
        raise _fetch_error(exc) from exc
    if "html" not in res.content_type.lower():
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "That URL isn't a web page")
    links = parse_generic(res.body, res.url)

    source = Source(
        kind=SourceKind.CUSTOM_URL,
        parser=ParserKey.GENERIC,
        name=body.name or (url.split("//", 1)[-1][:200]),
        url=url,
        owner_id=user.id,
        next_check_at=datetime.now(UTC),  # worker baselines it on the next tick
    )
    session.add(source)
    await session.commit()
    return SourceCreated(source=_out(source, user), already_tracked=False, preview=_preview(links))


@router.post("/telegram", response_model=SourceCreated, status_code=status.HTTP_201_CREATED)
async def add_telegram_channel(
    body: TelegramIn, user: CurrentUser, session: SessionDep, fetcher: FetcherDep, response: Response
) -> SourceCreated:
    """Track a public Telegram channel through its t.me/s/ web preview."""
    try:
        channel = normalize_channel(body.channel)
    except InvalidChannelError as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc)) from exc
    url = channel_preview_url(channel)
    if existing := await _existing(session, SourceKind.TELEGRAM, url):
        response.status_code = status.HTTP_200_OK
        return SourceCreated(source=_out(existing, user), already_tracked=True, preview=None)
    await _check_quota(session, user)

    try:
        page = await fetch_channel_page(
            fetcher, channel, before=None, max_bytes=get_settings().max_page_bytes
        )
    except FetchError as exc:
        raise _fetch_error(exc) from exc
    if not page.is_public_preview:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "Channel is private or has no public preview"
        )

    source = Source(
        kind=SourceKind.TELEGRAM,
        parser=ParserKey.TELEGRAM,
        name=f"Telegram · {page.title or channel}"[:200],
        url=url,
        owner_id=user.id,
        next_check_at=datetime.now(UTC),
    )
    session.add(source)
    await session.commit()
    return SourceCreated(
        source=_out(source, user), already_tracked=False, preview=_preview(messages_to_links(page.messages))
    )


@router.get("", response_model=list[SourceOut])
async def list_sources(user: CurrentUser, session: SessionDep) -> list[SourceOut]:
    """Built-in seeds plus the sources you added."""
    rows = await session.scalars(
        select(Source)
        .where(or_(Source.kind == SourceKind.SEED, Source.owner_id == user.id))
        .order_by(Source.kind, Source.name)
    )
    return [_out(s, user) for s in rows]


@router.delete("/{source_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_source(source_id: uuid.UUID, user: CurrentUser, session: SessionDep) -> None:
    source = await session.get(Source, source_id)
    if source is None or source.owner_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Source not found")
    await session.delete(source)
    await session.commit()


@router.get("/alerts", response_model=list[AlertOut])
async def recent_alerts(
    user: CurrentUser,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
) -> list[AlertOut]:
    """Admit card / exam date / postponed / corrigendum updates from seeds and your sources."""
    rows = await session.execute(
        select(DiscoveredItem, Source.name)
        .join(Source)
        .where(
            DiscoveredItem.kind == ItemKind.ALERT,
            DiscoveredItem.status != ItemStatus.BASELINE,
            or_(Source.kind == SourceKind.SEED, Source.owner_id == user.id),
        )
        .order_by(DiscoveredItem.created_at.desc())
        .limit(limit)
    )
    return [
        AlertOut.model_validate(
            {
                **{c: getattr(item, c) for c in AlertOut.model_fields if c != "source_name"},
                "source_name": name,
            }
        )
        for item, name in rows
    ]
