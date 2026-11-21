"""Tests for the named personas, the canary patient and the canary scan."""

import subprocess
from pathlib import Path

from synthdata.canary import CANARY_VALUES
from synthdata.generate import ANCHOR, generate, to_sql
from synthdata.personas import PERSONAS

SCAN = Path(__file__).resolve().parents[3] / "scripts" / "canary-scan.sh"


def by_mrn(ds):
    return {p.mrn: p for p in ds.patients}


def test_personas_have_fixed_ids_whatever_the_seed():
    a, b = by_mrn(generate(patients=10, seed=1)), by_mrn(generate(patients=10, seed=99))
    for persona in PERSONAS:
        assert a[persona.mrn].id == b[persona.mrn].id == persona.id


def test_the_named_personas_are_present():
    names = {p.given_name for p in generate(patients=10, seed=1).patients if p.mrn < "NG0000100"}
    assert {"Elena", "Marcus", "Sofia", "Ana", "Omar"} <= names


def test_personas_live_where_their_stories_need_them():
    people = {p.given_name: p for p in PERSONAS}
    assert people["Elena"].home_location == "cambridge"
    assert people["Marcus"].home_location == "quincy"
    assert people["Sofia"].age_on_anchor == 15 and people["Ana"].age_on_anchor >= 18
    assert people["Sofia"].family_name == people["Ana"].family_name


def test_exactly_one_canary():  # E26
    canaries = [p for p in generate(patients=200, seed=3).patients if p.is_canary]
    assert len(canaries) == 1


def test_canary_values_appear_only_in_the_canary_patient():
    ds = generate(patients=200, seed=3)
    for p in ds.patients:
        text = " ".join(str(v) for v in p.model_dump().values())
        assert any(v in text for v in CANARY_VALUES) == p.is_canary


def test_dr_chen_is_named_in_the_sql():
    assert "Dr Mei Chen (orthodontist)" in to_sql(generate(patients=1, seed=1))


def test_sofia_is_fifteen_on_the_anchor_date():
    sofia = next(p for p in PERSONAS if p.given_name == "Sofia")
    assert sofia.date_of_birth.replace(year=sofia.date_of_birth.year + 15) <= ANCHOR


def test_canary_scan_finds_a_planted_canary(tmp_path):
    leaky = tmp_path / "app.log"
    leaky.write_text(f"2026-11-18 INFO patient {CANARY_VALUES[0]} booked\n")
    result = subprocess.run([str(SCAN), str(leaky)], capture_output=True, text=True)
    assert result.returncode == 1 and "app.log" in result.stdout


def test_canary_scan_passes_clean_text(tmp_path):
    clean = tmp_path / "app.log"
    clean.write_text("2026-11-18 INFO patient 3f2a booked\n")
    assert subprocess.run([str(SCAN), str(clean)], capture_output=True).returncode == 0
