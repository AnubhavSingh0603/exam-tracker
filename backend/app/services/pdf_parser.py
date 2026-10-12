"""Gemini Flash PDF extractor.

Two stages:
  1. ``_call_gemini``         PDF -> ``NotificationExtraction`` (LLM schema, loosely typed)
  2. ``normalize_extraction`` -> ``ParsedNotification`` (strict types, sanity checks)

Stage 2 is pure and unit-testable. Anything suspicious is recorded in
``review_notes`` instead of failing the whole upload, so a half-good PDF is
still ingested and flagged ``needs_review`` for a human glance.
"""

from __future__ import annotations

import asyncio
import io
import logging
import re
from datetime import date, datetime, time
from functools import lru_cache
from pathlib import Path
from zoneinfo import ZoneInfo

from dateutil import parser as dateparser
from google import genai
from google.genai import errors as genai_errors
from google.genai import types
from pydantic import ValidationError
from tenacity import (
    AsyncRetrying,
    retry_if_exception,
    stop_after_attempt,
    wait_exponential_jitter,
)

from app.core.config import get_settings
from app.domain.enums import RELAXATION_KEY_EXSM, RELAXATION_KEY_PWBD, Category
from app.schemas.extraction import (
    ExtractedRelaxation,
    ExtractedVacancy,
    NotificationExtraction,
)
from app.schemas.notification import ParsedNotification, ParsedPost, ParsedVacancy
from app.services.pdf_slicer import select_relevant_pages

log = logging.getLogger(__name__)

INLINE_PDF_LIMIT = 18 * 1024 * 1024  # inline request cap is ~20 MB; larger goes via Files API
_RETRYABLE_HTTP = {429, 500, 502, 503, 504}


class ExtractionError(RuntimeError):
    """The PDF could not be turned into a usable notification."""


SYSTEM_INSTRUCTION = """\
You are a meticulous data-entry clerk for Indian Government / PSU recruitment notifications.
Extract facts ONLY from the attached PDF. Never guess or use outside knowledge.

Rules:
- If a value is not printed, return null (or an empty list). Do not infer.
- Copy numbers exactly as printed. Vacancy tables: map GEN/General/UR/Unreserved -> ur,
  OBC/OBC-NCL -> obc, PwBD/PH/PWD/Divyang -> pwbd, ESM/Ex-Servicemen -> ex_serviceman.
- If a post's vacancies are split across locations/units, sum them per category.
- Create one entry in `posts` per distinct post code / discipline.
- Dates must be YYYY-MM-DD (convert DD.MM.YYYY / DD-MM-YYYY). Times are 24h HH:MM.
- `age_as_on_date` is the date on which age is reckoned ("age as on ...").
- Age relaxation: list each category separately in years (SC, ST, OBC, EWS, PWBD, EXSM).
  For PwBD, give the relaxation for the UR PwBD candidate (usually 10).
- `eligible_degrees`: one short entry per degree+branch, e.g.
  "B.E./B.Tech Electronics & Communication", "B.E./B.Tech Electrical", "Any Graduate".
- Bilingual (Hindi/English) PDFs: use the English text.
"""

USER_PROMPT = "Extract the recruitment notification in this PDF into the required JSON schema."


@lru_cache
def _default_client() -> genai.Client:
    s = get_settings()
    return genai.Client(
        api_key=s.gemini_api_key.get_secret_value(),
        http_options=types.HttpOptions(timeout=s.gemini_timeout_s * 1000),  # milliseconds
    )


def _is_retryable(exc: BaseException) -> bool:
    return isinstance(exc, genai_errors.APIError) and exc.code in _RETRYABLE_HTTP


# =============================================================================
# Public API
# =============================================================================


async def extract_notification(
    pdf: bytes | str | Path,
    *,
    client: genai.Client | None = None,
    model: str | None = None,
) -> ParsedNotification:
    settings = get_settings()
    data = pdf if isinstance(pdf, bytes) else await asyncio.to_thread(Path(pdf).read_bytes)
    if not data.startswith(b"%PDF-"):
        raise ExtractionError("Input is not a PDF file.")

    try:
        selection = await asyncio.to_thread(
            select_relevant_pages,
            data,
            min_pages_to_slice=settings.pdf_slice_min_pages,
            max_pages=settings.pdf_slice_max_pages,
        )
    except Exception as exc:  # noqa: BLE001 - malformed PDFs: let Gemini try the original
        log.warning("Page slicing failed, sending the whole PDF: %s", exc)
        selection = None

    payload = selection.data if selection is not None else data
    raw = await _call_gemini(client or _default_client(), payload, model or settings.gemini_model)
    parsed = normalize_extraction(raw, tz=ZoneInfo(settings.timezone))
    # Only worth a reviewer's attention when something else already looks off.
    if selection is not None and selection.sliced and parsed.review_notes:
        parsed.review_notes.append(selection.describe())
    return parsed


# =============================================================================
# Stage 1: Gemini
# =============================================================================


async def _call_gemini(client: genai.Client, data: bytes, model: str) -> NotificationExtraction:
    config = types.GenerateContentConfig(
        system_instruction=SYSTEM_INSTRUCTION,
        response_mime_type="application/json",
        response_schema=NotificationExtraction,
        temperature=0.0,
        max_output_tokens=32768,
    )
    retrying = AsyncRetrying(
        retry=retry_if_exception(_is_retryable),
        wait=wait_exponential_jitter(initial=2, max=60),
        stop=stop_after_attempt(get_settings().gemini_max_attempts),
        reraise=True,
    )
    try:
        async for attempt in retrying:
            with attempt:
                response = await _generate(client, data, model, config)
    except genai_errors.APIError as exc:
        raise ExtractionError(f"Gemini API error {exc.code}: {exc.message}") from exc

    text = response.text
    if not text:
        reason = response.candidates[0].finish_reason if response.candidates else "no candidates"
        raise ExtractionError(f"Gemini returned an empty response ({reason}).")
    try:
        return NotificationExtraction.model_validate_json(text)
    except ValidationError as exc:
        raise ExtractionError(f"Gemini output failed schema validation: {exc}") from exc


async def _generate(
    client: genai.Client, data: bytes, model: str, config: types.GenerateContentConfig
) -> types.GenerateContentResponse:
    uploaded: types.File | None = None
    try:
        if len(data) <= INLINE_PDF_LIMIT:
            pdf_part: types.Part | types.File = types.Part.from_bytes(data=data, mime_type="application/pdf")
        else:
            uploaded = await client.aio.files.upload(
                file=io.BytesIO(data), config=types.UploadFileConfig(mime_type="application/pdf")
            )
            pdf_part = uploaded
        return await client.aio.models.generate_content(
            model=model, contents=[pdf_part, USER_PROMPT], config=config
        )
    finally:
        if uploaded is not None and uploaded.name:
            try:
                await client.aio.files.delete(name=uploaded.name)
            except Exception:  # noqa: BLE001 - cleanup is best-effort (files auto-expire in 48h)
                log.warning("Failed to delete uploaded Gemini file %s", uploaded.name)


# =============================================================================
# Stage 2: normalisation (pure)
# =============================================================================

_RELAX_ALIASES = {
    "SC": Category.SC.value,
    "ST": Category.ST.value,
    "SCST": None,  # ambiguous combined row; handled below
    "OBC": Category.OBC.value,
    "OBCNCL": Category.OBC.value,
    "EWS": Category.EWS.value,
    "PWBD": RELAXATION_KEY_PWBD,
    "PWD": RELAXATION_KEY_PWBD,
    "PH": RELAXATION_KEY_PWBD,
    "DIVYANG": RELAXATION_KEY_PWBD,
    "EXSM": RELAXATION_KEY_EXSM,
    "ESM": RELAXATION_KEY_EXSM,
    "EXSERVICEMEN": RELAXATION_KEY_EXSM,
    "EXSERVICEMAN": RELAXATION_KEY_EXSM,
}


def _parse_date(raw: str | None, label: str, notes: list[str]) -> date | None:
    if not raw:
        return None
    try:
        d = date.fromisoformat(raw.strip())
    except ValueError:
        try:
            d = dateparser.parse(raw, dayfirst=True).date()
        except (ValueError, OverflowError):
            notes.append(f"Unparseable {label}: {raw!r}")
            return None
    if not 2000 <= d.year <= 2100:
        notes.append(f"Implausible {label}: {d.isoformat()}")
        return None
    return d


def _parse_time(raw: str | None, notes: list[str]) -> time | None:
    if not raw:
        return None
    m = re.fullmatch(r"\s*(\d{1,2})[:.](\d{2})\s*", raw)
    if not m or int(m[1]) > 23 or int(m[2]) > 59:
        notes.append(f"Unparseable closing time {raw!r}; assumed 23:59.")
        return None
    return time(int(m[1]), int(m[2]))


def _relaxations(items: list[ExtractedRelaxation], notes: list[str]) -> dict[str, int]:
    out: dict[str, int] = {}
    for item in items:
        key = re.sub(r"[^A-Z]", "", item.category.upper())
        if not 0 <= item.years <= 20:
            notes.append(f"Ignored implausible relaxation {item.category}: {item.years} yrs")
            continue
        if key == "SCST":
            out.setdefault(Category.SC.value, item.years)
            out.setdefault(Category.ST.value, item.years)
            continue
        canon = _RELAX_ALIASES.get(key)
        if canon is None:
            notes.append(f"Unknown relaxation category {item.category!r} ignored")
            continue
        out[canon] = item.years
    return out


def _vacancy(v: ExtractedVacancy, label: str, notes: list[str]) -> ParsedVacancy:
    cats = {k: max(0, getattr(v, k) or 0) for k in ("ur", "sc", "st", "obc", "ews")}
    cat_sum = sum(cats.values())
    total = max(0, v.total) if v.total is not None else cat_sum
    if v.total is not None and cat_sum and cat_sum != v.total:
        notes.append(f"{label}: category seats sum to {cat_sum} but printed total is {v.total}")
    if cat_sum == 0 and total > 0:
        notes.append(f"{label}: category-wise vacancy break-up missing")
    return ParsedVacancy(
        **cats,
        total=total,
        pwbd=max(0, v.pwbd) if v.pwbd is not None else None,
        ex_serviceman=max(0, v.ex_serviceman) if v.ex_serviceman is not None else None,
    )


def _age(value: int | None, label: str, notes: list[str]) -> int | None:
    if value is None or 14 <= value <= 70:
        return value
    notes.append(f"Ignored implausible {label}: {value}")
    return None


def _clean_url(raw: str | None, notes: list[str]) -> str | None:
    if not raw:
        return None
    url = raw.strip()
    if url.lower().startswith("www."):
        url = "https://" + url
    if not re.match(r"^https?://[^\s/$.?#].[^\s]*$", url, re.IGNORECASE):
        notes.append(f"Ignored invalid portal URL {raw!r}")
        return None
    return url[:1000]


def _dedupe(items: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for s in (x.strip() for x in items):
        if s and s.lower() not in seen:
            seen.add(s.lower())
            out.append(s[:200])
    return out


def normalize_extraction(raw: NotificationExtraction, *, tz: ZoneInfo) -> ParsedNotification:
    notes: list[str] = []

    start = _parse_date(raw.application_start_date, "application start date", notes)
    end = _parse_date(raw.application_end_date, "application end date", notes)
    close_at = _parse_time(raw.application_end_time, notes) or time(23, 59, 59)
    deadline = datetime.combine(end, close_at, tzinfo=tz) if end else None
    if deadline is None:
        notes.append("Application deadline not found — job will not appear in the feed.")
    if start and end and start > end:
        notes.append(f"Start date {start} is after end date {end}")

    global_as_on = _parse_date(raw.age_as_on_date, "age cut-off date", notes)
    general_relax = _relaxations(raw.general_age_relaxations, notes)

    posts: list[ParsedPost] = []
    for i, p in enumerate(raw.posts, start=1):
        label = f"Post {p.post_code or i} ({p.post_name[:40]})"
        as_on = _parse_date(p.age_as_on_date, f"{label} age cut-off", notes) or global_as_on
        if as_on is None and end is not None:
            as_on = end
            notes.append(f"{label}: age cut-off not printed; assumed closing date {end}")
        min_age = _age(p.min_age, f"{label} min age", notes)
        max_age = _age(p.max_age_ur, f"{label} max age", notes)
        if min_age is not None and max_age is not None and min_age > max_age:
            notes.append(f"{label}: min age {min_age} > max age {max_age}")

        posts.append(
            ParsedPost(
                post_code=(p.post_code or "").strip()[:60] or None,
                post_name=p.post_name.strip()[:300] or f"Post {i}",
                min_age=min_age,
                base_max_age=max_age,
                age_as_on=as_on,
                eligible_streams=_dedupe(p.eligible_degrees),
                qualification_text=p.qualification_summary,
                age_relaxation_overrides={**general_relax, **_relaxations(p.age_relaxations, notes)},
                vacancy=_vacancy(p.vacancies, label, notes),
            )
        )

    if not posts:
        raise ExtractionError("No posts found in the notification.")

    return ParsedNotification(
        organization=raw.organization.strip()[:200] or "Unknown organisation",
        exam_name=raw.exam_name.strip()[:300] or "Untitled recruitment",
        advertisement_no=(raw.advertisement_no or "").strip()[:120] or None,
        portal_url=_clean_url(raw.official_portal_url, notes),
        application_start=datetime.combine(start, time(0, 0), tzinfo=tz) if start else None,
        application_deadline=deadline,
        exam_date=_parse_date(raw.exam_date, "exam date", notes),
        posts=posts,
        review_notes=notes,
    )
