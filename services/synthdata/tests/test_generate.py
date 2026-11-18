"""Tests for the synthetic dental data generator."""

import hashlib
import re

import pytest

from synthdata.generate import OFFERED, generate, to_sql
from synthdata.target import UnsafeTarget, check_target

TOOTH = re.compile(r"^([1-9]|[12][0-9]|3[0-2]|[A-T])$")


@pytest.fixture(scope="module")
def data():
    return generate(patients=400, seed=2026)


def test_same_seed_gives_identical_output():  # E22
    a = hashlib.sha256(to_sql(generate(patients=120, seed=7)).encode()).hexdigest()
    b = hashlib.sha256(to_sql(generate(patients=120, seed=7)).encode()).hexdigest()
    assert a == b


def test_different_seed_gives_different_output():
    assert to_sql(generate(patients=120, seed=7)) != to_sql(generate(patients=120, seed=8))


def test_generates_the_requested_number_of_patients(data):
    assert len(data.patients) == 400


def test_implants_only_at_back_bay(data):  # E25
    implants = [p for p in data.procedures if p.service == "D6010"]
    assert implants, "expected some implants in 400 patients"
    assert {p.location for p in implants} == {"back-bay"}


def test_every_procedure_is_a_service_its_location_offers(data):
    assert all(p.service in OFFERED[p.location] for p in data.procedures)


def test_children_mostly_belong_to_cambridge(data):
    children = [p for p in data.patients if p.age_on_anchor < 18]
    share = sum(p.home_location == "cambridge" for p in children) / len(children)
    assert share > 0.5


def test_dentures_and_extractions_lean_to_quincy(data):
    def per_patient(code, loc):
        n = sum(p.service == code and p.location == loc for p in data.procedures)
        return n / max(1, sum(p.home_location == loc for p in data.patients))

    assert per_patient("D7140", "quincy") > per_patient("D7140", "back-bay")
    assert all(p.location == "quincy" for p in data.procedures if p.service == "D5110")


def test_contact_details_are_fictional(data):  # E27
    for p in data.patients:
        assert p.email.endswith(".synthetic")
        assert re.fullmatch(r"\+1[2-9][0-9]{2}55501[0-9]{2}", p.phone)


def test_tooth_numbers_are_universal(data):  # E23
    teeth = [c.tooth for c in data.tooth_conditions] + [p.tooth for p in data.procedures if p.tooth]
    assert teeth and all(TOOTH.match(t) for t in teeth)


def test_young_children_have_primary_teeth_only(data):
    ages = {p.id: p.age_on_anchor for p in data.patients}
    young = [c for c in data.tooth_conditions if ages[c.patient_id] < 6]
    assert all(c.tooth.isalpha() for c in young)


def test_completed_procedures_have_a_date(data):
    assert all((p.status == "completed") == (p.performed_at is not None) for p in data.procedures)


def test_every_patient_is_marked_synthetic_in_sql(data):
    # is_synthetic is written as a literal true for every row, never taken from the data
    sql = to_sql(data)
    assert sql.count("insert into public.patients") == sql.count("v.deceased::timestamptz, true, v.canary from")


@pytest.mark.parametrize("url", [
    "postgresql://postgres.orrmekwuuicmofemmitu:pw@aws-1-us-east-1.pooler.supabase.com:5432/postgres",
    "postgresql://postgres:pw@db.orrmekwuuicmofemmitu.supabase.co:5432/postgres",
    "postgresql://postgres:pw@some-other-host.example:5432/postgres",
])
def test_refuses_production_and_unknown_databases(url):  # E28
    with pytest.raises(UnsafeTarget):
        check_target(url)


@pytest.mark.parametrize("url", [
    "postgresql://postgres.dxkfsslymzqbgtoijuut:pw@aws-1-us-east-1.pooler.supabase.com:5432/postgres",
    "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
    "postgresql://postgres:postgres@localhost:54322/postgres",
])
def test_allows_staging_and_local_databases(url):
    check_target(url)
