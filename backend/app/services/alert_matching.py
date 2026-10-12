"""Does a crawled alert ("SSC CGL Tier 1 Admit Card") name a specific exam? Pure."""

from __future__ import annotations

import re

_STOPWORDS = {
    "the",
    "of",
    "and",
    "for",
    "in",
    "to",
    "a",
    "an",
    "&",
    "admit",
    "card",
    "cards",
    "call",
    "letter",
    "hall",
    "ticket",
    "exam",
    "examination",
    "recruitment",
    "online",
    "form",
    "notification",
    "post",
    "posts",
    "various",
    "out",
    "released",
    "download",
    "phase",
    "tier",
    "stage",
    "limited",
    "ltd",
    "india",
    "indian",
    "government",
    "govt",
    "advt",
    "no",
}
_YEAR = re.compile(r"^(19|20)\d\d$")


def _tokens(text: str) -> set[str]:
    return {
        w
        for w in re.findall(r"[a-z0-9]+", text.lower())
        if len(w) > 1 and w not in _STOPWORDS and not _YEAR.match(w)
    }


def _acronyms(organization: str) -> set[str]:
    """Both 'rrb' (all words) and 'rb' (without stopwords) for 'Railway Recruitment Board'."""
    words = re.findall(r"[A-Za-z]+", organization)
    full = "".join(w[0] for w in words).lower()
    short = "".join(w[0] for w in words if w.lower() not in _STOPWORDS).lower()
    return {a for a in (full, short) if len(a) > 1}


# Words many exam names share ("Combined Graduate Level" vs "Combined Higher
# Secondary Level"): they count towards the overlap but can't identify an exam alone.
_WEAK = {
    "combined",
    "level",
    "graduate",
    "graduates",
    "higher",
    "secondary",
    "senior",
    "junior",
    "general",
    "common",
    "entrance",
    "test",
    "selection",
}


def alert_matches_job(alert_title: str, exam_name: str, organization: str | None) -> bool:
    """True when the alert names this exam, not just the same organisation.

    Needs >= 2 shared tokens, and the exam must be identified by a distinctive
    word or its acronym ("Combined Higher Secondary Level" -> "chsl"); an exam
    named only with generic words needs all of them. So "SSC CHSL Admit Card"
    doesn't match an SSC CGL application, "RRB Section Controller Admit Card"
    doesn't match RRB NTPC, and "SSC CGL Combined Graduate Level Answer Key"
    doesn't match CHSL.
    """
    alert = _tokens(alert_title)
    org_tokens = _tokens(organization or "") | _acronyms(organization or "")
    exam_words = _tokens(exam_name) - org_tokens
    strong = (exam_words - _WEAK) | (_acronyms(exam_name) - org_tokens)
    shared = alert & (exam_words | strong | org_tokens)
    if len(shared) < 2:
        return False
    if exam_words - _WEAK:
        return bool(alert & strong)
    return exam_words <= alert or bool(alert & strong)
