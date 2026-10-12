"""Canonicalise free-text qualifications so "B.Tech ECE" matches
"B.E. (Electronics & Communication Engineering)".

Pure, dependency-free. Unrecognised strings fall back to normalised string equality.
"""

from __future__ import annotations

import re
from collections.abc import Sequence
from dataclasses import dataclass

ANY_GRAD = "ANY_GRADUATE"

# Checked in order; first match wins.
_DEGREE_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("BE_BTECH", re.compile(r"\b(b ?tech|b ?e|bachelor of (engineering|technology)|b ?sc engg?|amie)\b")),
    ("ME_MTECH", re.compile(r"\b(m ?tech|m ?e|master of (engineering|technology))\b")),
    ("DIPLOMA", re.compile(r"\bdiploma\b")),
    ("MSC", re.compile(r"\bm ?sc\b")),
    ("BSC", re.compile(r"\bb ?sc\b")),
    ("MCA", re.compile(r"\bmca\b")),
    ("BCA", re.compile(r"\bbca\b")),
    ("MBA", re.compile(r"\b(mba|pgdm)\b")),
    ("CA", re.compile(r"\b(ca|chartered accountant|cma|icwa)\b")),
    ("BCOM", re.compile(r"\bb ?com\b")),
    (ANY_GRAD, re.compile(r"\b(graduat\w*|bachelor s? degree|any degree)\b")),
]

_BRANCH_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("ECE", re.compile(r"\b(ece|e and c|electronics and communications?)\b")),
    ("ETC", re.compile(r"\b(extc|e and tc|ete|electronics and tele ?communications?)\b")),
    ("EIE", re.compile(r"\b(eie|electronics and instrumentation)\b")),
    ("EEE", re.compile(r"\b(eee|electrical and electronics?)\b")),
    ("ELECTRONICS", re.compile(r"\belectronics\b")),
    ("EE", re.compile(r"\b(ee|electrical)\b")),
    ("INSTRUMENTATION", re.compile(r"\binstrumentation\b")),
    ("CSE", re.compile(r"\b(cse|cs|computer science|computer engineering|comp sc)\b")),
    ("IT", re.compile(r"\b(it|information technology)\b")),
    ("MECH", re.compile(r"\b(mechanical|mech|me)\b")),
    ("CIVIL", re.compile(r"\b(civil|ce)\b")),
    ("CHEM", re.compile(r"\b(chemical|che)\b")),
    ("METALLURGY", re.compile(r"\bmetallurg\w*\b")),
    ("PRODUCTION", re.compile(r"\b(production|industrial)\b")),
    ("AERO", re.compile(r"\b(aeronautical|aerospace)\b")),
    ("MINING", re.compile(r"\bmining\b")),
]

_ANY_BRANCH = re.compile(r"\b(any|all) (branch(es)?|disciplines?|streams?|engineering)\b")


def normalise(raw: str) -> str:
    s = raw.lower().replace("&", " and ").replace(".", "")
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


@dataclass(frozen=True, slots=True)
class Qualification:
    raw: str
    degree: str | None
    branch: str | None
    any_branch: bool

    @property
    def recognised(self) -> bool:
        return self.degree is not None or self.branch is not None or self.any_branch


def parse_qualification(raw: str) -> Qualification:
    text = normalise(raw)
    degree = next((code for code, pat in _DEGREE_PATTERNS if pat.search(text)), None)
    branch = next((code for code, pat in _BRANCH_PATTERNS if pat.search(text)), None)
    return Qualification(raw=text, degree=degree, branch=branch, any_branch=bool(_ANY_BRANCH.search(text)))


def _degree_ok(user: str | None, post: str | None) -> bool:
    if post is None:
        return True
    if post == ANY_GRAD:
        return user is not None and user != "DIPLOMA"
    return user == post


def _matches(user: Qualification, post: Qualification) -> bool:
    if not post.recognised:
        return user.raw == post.raw
    if not _degree_ok(user.degree, post.degree):
        return False
    return post.any_branch or post.branch is None or post.branch == user.branch


def match_streams(user_streams: Sequence[str], post_streams: Sequence[str]) -> bool | None:
    """True/False when decidable; None when the post lists no qualifications or the
    user has none on file (caller should surface "verify manually")."""
    if not post_streams or not user_streams:
        return None
    users = [parse_qualification(s) for s in user_streams]
    posts = [parse_qualification(s) for s in post_streams]
    return any(_matches(u, p) for u in users for p in posts)
