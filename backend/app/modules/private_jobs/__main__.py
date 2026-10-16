"""Builds private_jobs.json. A board that fails keeps its jobs from the previous file,
and if every board fails the previous file is written back unchanged, so a bad run
never empties the app's Private feed."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import httpx

from .boards import NORMALISE, fetch
from .companies import BOARDS

SCHEMA = 1


def build(previous: dict[str, Any] | None, client: httpx.Client) -> dict[str, Any]:
    old_by_board: dict[str, list[dict[str, Any]]] = {}
    for job in (previous or {}).get("jobs", []):
        kind, token, _ = job["id"].split(":", 2)
        old_by_board.setdefault(f"{kind}:{token}", []).append(job)

    jobs: list[dict[str, Any]] = []
    sources: list[dict[str, Any]] = []
    for board in BOARDS:
        key = f"{board.kind}:{board.token}"
        try:
            found = NORMALISE[board.kind](board, fetch(board, client))
            sources.append({"board": key, "company": board.company, "jobs": len(found), "ok": True})
        except Exception as e:  # one board down must not cost the others
            found = old_by_board.get(key, [])
            sources.append(
                {
                    "board": key,
                    "company": board.company,
                    "jobs": len(found),
                    "ok": False,
                    "error": str(e)[:200],
                }
            )
        jobs.extend(found)

    jobs.sort(key=lambda j: j.get("posted_at") or "", reverse=True)
    return {"schema": SCHEMA, "generated_at": datetime.now(UTC).isoformat(), "sources": sources, "jobs": jobs}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m app.modules.private_jobs")
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--previous", type=Path, help="last published private_jobs.json, if any")
    args = parser.parse_args(argv)

    previous = None
    if args.previous and args.previous.is_file() and args.previous.stat().st_size:
        try:
            previous = json.loads(args.previous.read_text(encoding="utf-8"))
        except ValueError:
            previous = None

    with httpx.Client(follow_redirects=True) as client:
        result = build(previous, client)

    if not any(s["ok"] for s in result["sources"]) and previous:
        result = previous  # nothing reachable: keep what the app already has
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    ok = sum(s["ok"] for s in result.get("sources", []))
    print(f"private_jobs.json: {len(result.get('jobs', []))} jobs from {ok}/{len(BOARDS)} boards")
    return 0


if __name__ == "__main__":
    sys.exit(main())
