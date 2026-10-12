"""Broad degree-level qualification model.

Qualifications are matched by tier (10th < 12th < Diploma/ITI < UG < PG < PhD)
and by degree title (B.Tech, B.Sc, MBA, ...). No branch/specialisation
taxonomy: notification PDFs word branches too inconsistently to match reliably.
Unlisted degrees use OTHERS plus free text, matched by keyword search.

Single source of truth for both ends: ``scripts/export_taxonomy.py`` generates
``mobile/lib/domain/qualification_taxonomy.g.dart`` from this module, and a test
keeps the two in sync. Codes are stable wire values.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class QualificationLevel(StrEnum):
    MATRIC = "MATRIC"
    INTERMEDIATE = "INTERMEDIATE"
    DIPLOMA = "DIPLOMA"
    UG = "UG"
    PG = "PG"
    PHD = "PHD"

    @property
    def rank(self) -> int:
        return _LEVEL_RANK[self]


_LEVEL_RANK = {
    QualificationLevel.MATRIC: 1,
    QualificationLevel.INTERMEDIATE: 2,
    QualificationLevel.DIPLOMA: 3,
    QualificationLevel.UG: 4,
    QualificationLevel.PG: 5,
    QualificationLevel.PHD: 6,
}

LEVEL_LABELS: dict[QualificationLevel, str] = {
    QualificationLevel.MATRIC: "10th / Matriculation",
    QualificationLevel.INTERMEDIATE: "12th / Intermediate",
    QualificationLevel.DIPLOMA: "Diploma / ITI",
    QualificationLevel.UG: "Graduation (UG)",
    QualificationLevel.PG: "Post-Graduation (PG)",
    QualificationLevel.PHD: "Doctorate (Ph.D)",
}

OTHERS = "OTHERS"


@dataclass(frozen=True, slots=True)
class Degree:
    code: str
    label: str
    level: QualificationLevel
    group: str  # heading in the picker
    # PG degrees: the bachelor's every holder has, so a "B.Tech" post also matches an M.Tech.
    implies: str | None = None


_L = QualificationLevel
DEGREES: tuple[Degree, ...] = (
    Degree("CLASS_10", "10th / Matriculation", _L.MATRIC, "School / Basic"),
    Degree("CLASS_12", "12th / Intermediate", _L.INTERMEDIATE, "School / Basic"),
    Degree("ITI", "ITI", _L.DIPLOMA, "School / Basic"),
    Degree("DIPLOMA", "Diploma / Polytechnic", _L.DIPLOMA, "School / Basic"),
    Degree("B_TECH", "B.Tech / B.E.", _L.UG, "Undergraduate (UG)"),
    Degree("B_SC", "B.Sc", _L.UG, "Undergraduate (UG)"),
    Degree("B_COM", "B.Com", _L.UG, "Undergraduate (UG)"),
    Degree("B_A", "B.A.", _L.UG, "Undergraduate (UG)"),
    Degree("BBA", "BBA / BMS", _L.UG, "Undergraduate (UG)"),
    Degree("BCA", "BCA", _L.UG, "Undergraduate (UG)"),
    Degree("LLB", "LL.B", _L.UG, "Undergraduate (UG)"),
    Degree("B_ED", "B.Ed", _L.UG, "Undergraduate (UG)"),
    Degree("B_PHARM", "B.Pharm", _L.UG, "Undergraduate (UG)"),
    Degree("MBBS", "MBBS / BDS", _L.UG, "Undergraduate (UG)"),
    Degree("B_ARCH", "B.Arch", _L.UG, "Undergraduate (UG)"),
    Degree("M_TECH", "M.Tech / M.E.", _L.PG, "Postgraduate (PG)", implies="B_TECH"),
    Degree("M_SC", "M.Sc", _L.PG, "Postgraduate (PG)", implies="B_SC"),
    Degree("M_COM", "M.Com", _L.PG, "Postgraduate (PG)", implies="B_COM"),
    Degree("M_A", "M.A.", _L.PG, "Postgraduate (PG)", implies="B_A"),
    Degree("MBA", "MBA / PGDM", _L.PG, "Postgraduate (PG)"),
    Degree("MCA", "MCA", _L.PG, "Postgraduate (PG)"),
    Degree("LLM", "LL.M", _L.PG, "Postgraduate (PG)", implies="LLB"),
    Degree("M_ED", "M.Ed", _L.PG, "Postgraduate (PG)", implies="B_ED"),
    Degree("M_PHARM", "M.Pharm", _L.PG, "Postgraduate (PG)", implies="B_PHARM"),
    Degree("MD_MS", "MD / MS", _L.PG, "Postgraduate (PG)", implies="MBBS"),
    Degree("PHD", "Ph.D / Doctorate", _L.PHD, "Doctorate"),
)

DEGREES_BY_CODE: dict[str, Degree] = {d.code: d for d in DEGREES}


def degree_codes_held(degree_title: str | None) -> set[str]:
    """The degree itself plus what it implies (M.Tech -> B.Tech)."""
    held: set[str] = set()
    code = degree_title
    while code and code not in held and code in DEGREES_BY_CODE:
        held.add(code)
        code = DEGREES_BY_CODE[code].implies
    return held


def taxonomy_as_dict() -> dict[str, object]:
    """Plain data for the client generator, the meta endpoint and tests."""
    return {
        "levels": [
            {"code": lv.value, "label": LEVEL_LABELS[lv], "rank": lv.rank} for lv in QualificationLevel
        ],
        "degrees": [
            {"code": d.code, "label": d.label, "level": d.level.value, "group": d.group, "implies": d.implies}
            for d in DEGREES
        ],
        "others_code": OTHERS,
    }
