"""Fetch and normalise postings from each job-board kind into one shape."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import httpx

from . import extract
from .companies import Board

_TIMEOUT = httpx.Timeout(30.0)
_HEADERS = {"User-Agent": "JobSummit/1.0 (+https://jobsummit.github.io/JobSummit/)"}

URLS = {
    "greenhouse": "https://boards-api.greenhouse.io/v1/boards/{token}/jobs?content=true",
    "lever": "https://api.lever.co/v0/postings/{token}?mode=json",
    "ashby": "https://api.ashbyhq.com/posting-api/job-board/{token}?includeCompensation=true",
}


def fetch(board: Board, client: httpx.Client) -> Any:
    res = client.get(URLS[board.kind].format(token=board.token), headers=_HEADERS, timeout=_TIMEOUT)
    res.raise_for_status()
    return res.json()


def _job(
    board: Board,
    *,
    source_id: str,
    title: str,
    locations: list[str],
    remote: bool,
    employment: str,
    text: str,
    posted_at: str | None,
    apply_url: str,
    team: str | None,
    salary: str | None = None,
) -> dict[str, Any]:
    lo, hi, exp_from = extract.experience(title, text)
    return {
        "id": f"{board.kind}:{board.token}:{source_id}",
        "source": board.kind,
        "company": board.company,
        "title": title.strip(),
        "team": team or None,
        "locations": [loc for loc in dict.fromkeys(locations) if loc],
        "remote": remote,
        "employment_type": employment,
        "experience_min": lo,
        "experience_max": hi,
        "experience_from": exp_from,
        "skills": extract.skills(title, text, team),
        "salary": salary,
        "posted_at": posted_at,
        "apply_url": apply_url,
        "summary": extract.summary(text),
        # Board feeds are the employers' own careers pages: never an agency.
        "is_agency": False,
    }


def greenhouse(board: Board, data: dict[str, Any]) -> list[dict[str, Any]]:
    out = []
    for j in data.get("jobs", []):
        location = (j.get("location") or {}).get("name") or ""
        offices = [o.get("name") or "" for o in j.get("offices") or []]
        if not extract.in_india(location, *offices):
            continue
        departments = [d.get("name") for d in j.get("departments") or [] if d.get("name")]
        out.append(
            _job(
                board,
                source_id=str(j["id"]),
                title=j.get("title") or "",
                locations=[location],
                remote="remote" in location.lower(),
                employment=extract.employment_type(j.get("title")),
                text=extract.html_to_text(j.get("content")),
                posted_at=j.get("first_published") or j.get("updated_at"),
                apply_url=j.get("absolute_url") or "",
                team=departments[0] if departments else None,
            )
        )
    return out


def lever(board: Board, data: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out = []
    for j in data:
        cats = j.get("categories") or {}
        locations = [cats.get("location") or "", *(cats.get("allLocations") or [])]
        if j.get("country") != "IN" and not extract.in_india(*locations):
            continue
        parts = [j.get("descriptionPlain") or "", j.get("openingPlain") or ""]
        parts += [
            f"{lst.get('text', '')} {extract.html_to_text(lst.get('content'))}"
            for lst in j.get("lists") or []
        ]
        parts.append(j.get("additionalPlain") or "")
        created = j.get("createdAt")
        salary = j.get("salaryRange") or None
        out.append(
            _job(
                board,
                source_id=str(j["id"]),
                title=j.get("text") or "",
                locations=[loc.title() if loc.islower() else loc for loc in locations],
                remote=(j.get("workplaceType") or "") == "remote",
                employment=extract.employment_type(cats.get("commitment")),
                text=" ".join(p for p in parts if p).strip(),
                posted_at=datetime.fromtimestamp(int(created) / 1000, UTC).isoformat() if created else None,
                apply_url=j.get("hostedUrl") or j.get("applyUrl") or "",
                team=cats.get("team") or cats.get("department"),
                salary=_lever_salary(salary),
            )
        )
    return out


def _lever_salary(s: dict[str, Any] | None) -> str | None:
    if not s or not s.get("min"):
        return None
    cur = s.get("currency") or ""
    return f"{cur} {s['min']:,}–{s.get('max') or s['min']:,} / {s.get('interval', 'year')}".strip()


def ashby(board: Board, data: dict[str, Any]) -> list[dict[str, Any]]:
    out = []
    for j in data.get("jobs", []):
        if j.get("isListed") is False:
            continue
        locations = [j.get("location") or ""] + [
            s.get("location") or "" for s in j.get("secondaryLocations") or []
        ]
        country = ((j.get("address") or {}).get("postalAddress") or {}).get("addressCountry") or ""
        if not extract.in_india(*locations, country):
            continue
        comp = j.get("compensation") or {}
        out.append(
            _job(
                board,
                source_id=str(j["id"]),
                title=j.get("title") or "",
                locations=locations,
                remote=bool(j.get("isRemote")),
                employment=extract.employment_type(j.get("employmentType")),
                text=j.get("descriptionPlain") or extract.html_to_text(j.get("descriptionHtml")),
                posted_at=j.get("publishedAt"),
                apply_url=j.get("jobUrl") or j.get("applyUrl") or "",
                team=j.get("team") or j.get("department"),
                salary=comp.get("scrapeableCompensationSalarySummary") or comp.get("compensationTierSummary"),
            )
        )
    return out


NORMALISE = {"greenhouse": greenhouse, "lever": lever, "ashby": ashby}
