"""Backup reader for when every Gemini model is out of free quota for the day.

Mistral's free tier (one account, a different company: allowed) reads the text of
the notification, which the pipeline takes from the PDF itself with PyMuPDF, and
answers in the same JSON form as Gemini. Scanned PDFs have no text to read: those
wait for Gemini's quota to come back.
"""

from __future__ import annotations

import json
import logging
from typing import Any

import httpx
import pymupdf
from pydantic import BaseModel, ValidationError
from tenacity import AsyncRetrying, retry_if_exception, stop_after_attempt, wait_exponential_jitter

from app.core.config import get_settings
from app.schemas.extraction import ExtractedPost, ExtractedVacancy, NotificationExtraction

log = logging.getLogger(__name__)

API_URL = "https://api.mistral.ai/v1/chat/completions"
MAX_TEXT_CHARS = 60_000  # ~15k tokens: the relevant pages of even a long notification
MIN_TEXT_CHARS = 400  # less than this is a scanned PDF (or an empty page)


class MistralError(RuntimeError):
    """Mistral couldn't read this one (bad answer, unknown model, server error)."""


class MistralOutOfQuota(MistralError):
    """Rate-limited or out of quota: try again on a later run."""


def configured() -> bool:
    key = get_settings().mistral_api_key.get_secret_value().strip()
    return bool(key) and key.lower() not in {"unset", "none", "changeme"}


def models() -> list[str]:
    return [m.strip() for m in get_settings().mistral_models.split(",") if m.strip()]


def pdf_text(data: bytes) -> str:
    """The text layer, page by page ("" for a scanned PDF)."""
    with pymupdf.open(stream=data, filetype="pdf") as doc:
        pages = [f"--- Page {i} ---\n{page.get_text().strip()}" for i, page in enumerate(doc, start=1)]
    text = "\n\n".join(pages)
    return text if len(text.replace("--- Page", "")) >= MIN_TEXT_CHARS else ""


def _schema_text() -> str:
    return json.dumps(NotificationExtraction.model_json_schema(), separators=(",", ":"))


def _fill_missing(data: Any, model: type[BaseModel]) -> Any:
    """Missing keys become null / [] so a near-complete answer still validates; the
    normaliser then treats them as "not printed", as it does for Gemini."""
    if not isinstance(data, dict):
        return data
    nested = {"posts": ExtractedPost, "vacancies": ExtractedVacancy}
    out = dict(data)
    for name, field in model.model_fields.items():
        if name not in out or out[name] is None and "list" in str(field.annotation):
            out[name] = [] if "list" in str(field.annotation) else None
        if name in nested:
            sub = nested[name]
            if name == "posts" and isinstance(out[name], list):
                out[name] = [_fill_missing(p, sub) for p in out[name]]
            elif isinstance(out[name], dict):
                out[name] = _fill_missing(out[name], sub)
            elif name == "vacancies":
                out[name] = _fill_missing({}, sub)
    return out


def _retryable(exc: BaseException) -> bool:
    return isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code in {429, 500, 502, 503, 504}


async def extract(
    text: str, *, system: str, client: httpx.AsyncClient | None = None
) -> tuple[NotificationExtraction, str]:
    """One notification's text -> the extraction schema. Returns ``(raw, model)``."""
    settings = get_settings()
    own = client is None
    http = client or httpx.AsyncClient(timeout=settings.mistral_timeout_s)
    headers = {"Authorization": f"Bearer {settings.mistral_api_key.get_secret_value()}"}
    prompt = (
        f"{system}\nReply with ONE JSON object that follows this JSON schema exactly "
        f"(every key present; null when not printed):\n{_schema_text()}"
    )
    last: MistralError | None = None
    try:
        for model in models():
            body = {
                "model": model,
                "temperature": 0,
                "response_format": {"type": "json_object"},
                "messages": [
                    {"role": "system", "content": prompt},
                    {"role": "user", "content": f"Notification text:\n\n{text[:MAX_TEXT_CHARS]}"},
                ],
            }
            try:
                response = None
                async for attempt in AsyncRetrying(
                    retry=retry_if_exception(_retryable),
                    wait=wait_exponential_jitter(initial=3, max=40),
                    stop=stop_after_attempt(3),
                    reraise=True,
                ):
                    with attempt:
                        response = await http.post(API_URL, headers=headers, json=body)
                        response.raise_for_status()
            except httpx.HTTPStatusError as exc:
                code = exc.response.status_code
                if code == 429:
                    raise MistralOutOfQuota(f"Mistral rate limit ({model})") from exc
                last = MistralError(f"Mistral API error {code} ({model}): {exc.response.text[:200]}")
                if code in {400, 404}:
                    continue  # unknown model name: try the next one
                raise last from exc
            except httpx.TransportError as exc:
                raise MistralOutOfQuota(f"Mistral did not answer ({type(exc).__name__})") from exc
            try:
                content = response.json()["choices"][0]["message"]["content"]
                data = json.loads(content)
                return NotificationExtraction.model_validate(
                    _fill_missing(data, NotificationExtraction)
                ), model
            except (KeyError, IndexError, TypeError, ValueError, ValidationError) as exc:
                raise MistralError(f"Mistral's answer didn't fit the schema: {exc}") from exc
        raise last or MistralError("No Mistral model configured")
    finally:
        if own:
            await http.aclose()
