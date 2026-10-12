"""Read degree requirements out of a notification's free-text eligibility lines.

"B.E./B.Tech (Electronics & Communication)" -> degree B_TECH, level UG.
"Graduation in any discipline"              -> any graduate.
Branches are deliberately ignored (see app.domain.qualifications).

Pure, dependency-free apart from the taxonomy enums.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Sequence
from dataclasses import dataclass

from app.domain.qualifications import DEGREES_BY_CODE, QualificationLevel

ANY_GRAD = "ANY_GRADUATE"
ANY_PG = "ANY_POST_GRADUATE"

_L = QualificationLevel
_PSEUDO_LEVEL = {ANY_GRAD: _L.UG, ANY_PG: _L.PG}

# Checked in order; first match wins. Specific degrees before the generic
# "post graduate" / "graduate" catch-alls (PG before UG for that reason).
_DEGREE_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("B_ED", re.compile(r"\b(b ?ed|bachelor of education)\b")),
    ("M_ED", re.compile(r"\b(m ?ed|master of education)\b")),
    ("B_PHARM", re.compile(r"\b(b ?pharm\w*|bachelor of pharmacy)\b")),
    ("M_PHARM", re.compile(r"\b(m ?pharm\w*|master of pharmacy)\b")),
    ("B_ARCH", re.compile(r"\b(b ?arch\w*|bachelor of architecture)\b")),
    ("MBBS", re.compile(r"\b(mbbs|bds|bachelor of (medicine|dental surgery))\b")),
    ("MD_MS", re.compile(r"\b(md|ms|mds|doctor of medicine|master of surgery)\b")),
    (
        "B_TECH",
        re.compile(
            r"\b(b ?tech|b ?e|bachelor of (engineering|technology)|b ?sc engg?|amie"
            r"|degree in (any )?engineering|engineering (graduate|degree)|graduate (in|of) engineering)\b"
        ),
    ),
    ("M_TECH", re.compile(r"\b(m ?tech|m ?e|master of (engineering|technology))\b")),
    ("DIPLOMA", re.compile(r"\b(diploma|polytechnic)\b")),
    ("ITI", re.compile(r"\b(iti|ncvt|scvt|industrial training)\b")),
    ("M_SC", re.compile(r"\b(m ?sc|master of science)\b")),
    ("B_SC", re.compile(r"\b(b ?sc|bachelor of science)\b")),
    ("MCA", re.compile(r"\b(mca|master of computer applications?)\b")),
    ("BCA", re.compile(r"\b(bca|bachelor of computer applications?)\b")),
    ("MBA", re.compile(r"\b(mba|pgdm|pgdbm|master of business administration)\b")),
    ("M_COM", re.compile(r"\b(m ?com|master of commerce)\b")),
    ("B_COM", re.compile(r"\b(b ?com|bachelor of commerce)\b")),
    ("LLM", re.compile(r"\b(ll ?m|master of laws?)\b")),
    ("LLB", re.compile(r"\b(ll ?b|bachelor of laws?)\b")),
    ("BBA", re.compile(r"\b(bba|bms|bachelor of business administration)\b")),
    ("M_A", re.compile(r"\b(m ?a|master of arts)\b")),
    ("B_A", re.compile(r"\b(b ?a|bachelor of arts)\b")),
    ("PHD", re.compile(r"\b(ph ?d|doctorate|doctoral)\b")),
    (
        "CLASS_12",
        re.compile(
            r"\b(12th|12 th|xii|class 12|intermediate|10 2|hsc|higher secondary|senior secondary|plus two)\b"
        ),
    ),
    (
        "CLASS_10",
        re.compile(r"\b(10th|10 th|class 10|class x|matric\w*|high school|secondary school|sslc)\b"),
    ),
    (
        ANY_PG,
        re.compile(
            r"\b(post ?graduat\w*|pg degree|master s degree|masters degree|master degree|any master)\b"
        ),
    ),
    (ANY_GRAD, re.compile(r"\b(graduat\w*|bachelor s? degree|any degree)\b")),
]

# "Graduate with knowledge of computers" requires a graduate, nothing more:
# everything from the first skill/extra-requirement word on is dropped.
_EXTRA_REQUIREMENT = re.compile(r"\b(knowledge|proficiency|typing|certificat\w*|experience|skill\w*)\b")


def normalise(raw: str) -> str:
    s = raw.lower().replace("&", " and ").replace(".", "")
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


@dataclass(frozen=True, slots=True)
class DegreeLine:
    raw: str
    degree: str | None  # a DEGREES_BY_CODE key, ANY_GRAD, ANY_PG, or None (unrecognised)

    @property
    def level(self) -> QualificationLevel | None:
        if self.degree is None:
            return None
        if self.degree in _PSEUDO_LEVEL:
            return _PSEUDO_LEVEL[self.degree]
        return DEGREES_BY_CODE[self.degree].level


def parse_degree_line(raw: str) -> DegreeLine:
    text = _EXTRA_REQUIREMENT.split(normalise(raw), maxsplit=1)[0].strip()
    degree = next((code for code, pat in _DEGREE_PATTERNS if pat.search(text)), None)
    return DegreeLine(raw=text, degree=degree)


@dataclass(frozen=True, slots=True)
class PostRequirement:
    """What a post's eligibility lines imply."""

    allowed_degrees: tuple[str, ...]  # real degree codes only, in order, de-duplicated
    min_level: QualificationLevel | None
    open_to_any_graduate: bool
    open_to_any_post_graduate: bool


def infer_requirement(lines: Sequence[str]) -> PostRequirement:
    parsed = [parse_degree_line(s) for s in lines]
    levels = [p.level for p in parsed if p.level is not None]
    degrees = [p.degree for p in parsed if p.degree and p.degree in DEGREES_BY_CODE]
    return PostRequirement(
        allowed_degrees=tuple(dict.fromkeys(degrees)),
        min_level=min(levels, key=lambda lv: lv.rank) if levels else None,
        open_to_any_graduate=any(p.degree == ANY_GRAD for p in parsed),
        open_to_any_post_graduate=any(p.degree == ANY_PG for p in parsed),
    )


# --- "Others": keyword search of free text ------------------------------------

_SPLIT_ALTERNATIVES = re.compile(r"[/,;|]| or ", re.IGNORECASE)
_STOP = {"in", "of", "the", "and", "degree", "course", "with", "from", "a", "an"}
# Too generic to match on their own ("Bachelor" would match every degree line).
_GENERIC = {"bachelor", "bachelors", "master", "masters", "diploma", "graduate", "graduation", "post"}


def _content_words(text: str) -> list[str]:
    return [w for w in normalise(text).split() if w not in _STOP]


def custom_terms(custom_text: str) -> list[str]:
    """'CA/CS' -> ['ca', 'cs']; 'B Des (Fashion)' -> ['b des fashion', 'bdes']."""
    terms: list[str] = []
    for part in _SPLIT_ALTERNATIVES.split(custom_text):
        words = _content_words(part)
        if not words:
            continue
        terms.append(" ".join(words))
        # Abbreviations are printed both "B.Des" and "B Des": also try the joined head.
        if len(words) >= 2 and len(words[0]) <= 2:
            terms.append(words[0] + words[1])
        elif len(words) >= 2 and len(words[0]) >= 3 and words[0] not in _GENERIC:
            terms.append(words[0])  # "BAMS Ayurveda" -> also "bams"
    return list(dict.fromkeys(t for t in terms if len(t) >= 2 and t not in _GENERIC))


def custom_text_matches(custom_text: str, haystacks: Iterable[str]) -> bool:
    """Case-insensitive whole-word search of any alternative in any haystack."""
    terms = custom_terms(custom_text)
    if not terms:
        return False
    texts = [" ".join(_content_words(h)) for h in haystacks if h]
    for term in terms:
        pattern = re.compile(rf"\b{re.escape(term)}\b")
        if any(pattern.search(t) for t in texts):
            return True
    return False
