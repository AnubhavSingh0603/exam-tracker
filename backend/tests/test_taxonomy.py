import importlib.util
from pathlib import Path

import pytest

from app.domain.qualifications import DEGREES, DEGREES_BY_CODE, OTHERS, degree_codes_held, taxonomy_as_dict

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "export_taxonomy.py"


def _exporter():
    spec = importlib.util.spec_from_file_location("export_taxonomy", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_flutter_copy_is_up_to_date():
    exporter = _exporter()
    if not exporter.DART_FILE.parent.exists():
        pytest.skip("mobile/ not present (backend-only checkout)")
    assert exporter.DART_FILE.read_text(encoding="utf-8") == exporter.render(), (
        "Run: python backend/scripts/export_taxonomy.py"
    )


def test_codes_are_unique_and_implications_resolve():
    codes = [d.code for d in DEGREES]
    assert len(codes) == len(set(codes)) and OTHERS not in codes
    for d in DEGREES:
        if d.implies:
            assert DEGREES_BY_CODE[d.implies].level.rank < d.level.rank


def test_degree_codes_held():
    assert degree_codes_held("M_TECH") == {"M_TECH", "B_TECH"}
    assert degree_codes_held(OTHERS) == set()


def test_taxonomy_shape():
    data = taxonomy_as_dict()
    assert data["others_code"] == OTHERS
    assert {"code", "label", "level", "group", "implies"} <= set(data["degrees"][0])
