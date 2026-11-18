"""Generate synthetic dental patients and records for Northgate Dental.

Everything is derived from one seed and a fixed anchor date, so the same seed always produces the same
data (E22). Records are validated with Pydantic, then written as idempotent SQL: ids are deterministic
and every insert uses `on conflict (id) do nothing`, so loading twice changes nothing.
Fees are not known here; the SQL takes each fee from the location's price list at load time.
"""

import random
import unicodedata
import uuid
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta, timezone

from faker import Faker
from pydantic import BaseModel, Field

ANCHOR = date(2026, 11, 1)                     # fixed "today" so output never depends on the clock
NAMESPACE = uuid.UUID("6b1f3f0e-4f7d-4c1e-9c63-2d0d9c5a7e10")
FIRST_GENERATED_MRN = 100                      # NG0000001 to NG0000099 are reserved for personas

# Services each location offers (codes only; prices live in the database). Mirrors supabase/seed.sql;
# a mismatch is refused at load time by the dental_procedures foreign key.
OFFERED = {
    "back-bay": {"D0150", "D1110", "D2391", "D7140", "D3330", "D6010", "D8090", "D9110"},
    "cambridge": {"D0150", "D1110", "D1120", "D2391", "D8090", "D9972"},
    "quincy": {"D0150", "D1110", "D2391", "D7140", "D5110", "D9110"},
}

# Who performs what, by seeded profile id (stable even if display names change).
P = {k: f"10000000-0000-4000-8000-0000000000{n:02d}" for k, n in
     {"oral_surgeon": 8, "endodontist": 9, "hygienist": 10, "orthodontist": 11, "paediatric": 12, "quincy": 13}.items()}
PERFORMER = {
    "back-bay": {"D0150": "endodontist", "D1110": "hygienist", "D2391": "endodontist", "D7140": "oral_surgeon",
                 "D3330": "endodontist", "D6010": "oral_surgeon", "D8090": "orthodontist", "D9110": "oral_surgeon"},
    "cambridge": {"D0150": "paediatric", "D1110": "paediatric", "D1120": "paediatric", "D2391": "paediatric",
                  "D8090": "orthodontist", "D9972": "paediatric"},
    "quincy": {code: "quincy" for code in OFFERED["quincy"]},
}

TOOTH = r"^([1-9]|[12][0-9]|3[0-2]|[A-T])$"
PERMANENT = [str(n) for n in range(1, 33)]
PRIMARY = list("ABCDEFGHIJKLMNOPQRST")


class Patient(BaseModel):
    id: str
    mrn: str = Field(pattern=r"^NG[0-9]{7}$")
    given_name: str
    family_name: str
    date_of_birth: date
    sex_at_birth: str = Field(pattern="^(female|male|unknown)$")
    home_location: str
    email: str = Field(pattern=r"^[a-z0-9._-]+@([a-z0-9-]+\.)*synthetic$")
    phone: str = Field(pattern=r"^\+1[2-9][0-9]{2}55501[0-9]{2}$")
    preferred_language: str = Field(pattern="^(en|es)$")
    deceased_at: datetime | None = None
    is_canary: bool = False
    age_on_anchor: int


class Encounter(BaseModel):
    id: str
    patient_id: str
    location: str
    performer: str
    occurred_at: datetime
    kind: str = Field(pattern="^(exam|hygiene|treatment|emergency|consultation)$")


class ToothCondition(BaseModel):
    id: str
    patient_id: str
    encounter_id: str | None
    tooth: str = Field(pattern=TOOTH)
    condition: str
    recorded_at: datetime


class Plan(BaseModel):
    id: str
    patient_id: str
    location: str
    status: str
    created_at: datetime


class Phase(BaseModel):
    id: str
    plan_id: str
    patient_id: str
    sequence: int
    name: str


class Procedure(BaseModel):
    id: str
    patient_id: str
    location: str
    service: str
    performer: str
    encounter_id: str | None
    plan_phase_id: str | None
    tooth: str | None = Field(default=None, pattern=TOOTH)
    status: str
    performed_at: datetime | None

    @property
    def home_location(self) -> str:  # convenience for tests that weigh by patient location
        return self.location


@dataclass
class Dataset:
    patients: list[Patient] = field(default_factory=list)
    encounters: list[Encounter] = field(default_factory=list)
    tooth_conditions: list[ToothCondition] = field(default_factory=list)
    plans: list[Plan] = field(default_factory=list)
    phases: list[Phase] = field(default_factory=list)
    procedures: list[Procedure] = field(default_factory=list)


def _id(*parts: object) -> str:
    return str(uuid.uuid5(NAMESPACE, "/".join(map(str, parts))))


def _ascii(s: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", s.lower()) if c.isalnum())


def _at(day: date, rng: random.Random) -> datetime:
    hour = rng.choice([13, 14, 15, 16, 17, 18, 19, 20, 21])  # 08:00 to 16:00 Boston, in UTC
    return datetime.combine(day, time(hour, 0), tzinfo=timezone.utc)


def _home(age: int, rng: random.Random) -> str:
    if age < 18:
        return rng.choices(["cambridge", "back-bay", "quincy"], [0.6, 0.2, 0.2])[0]
    return rng.choices(["back-bay", "cambridge", "quincy"], [0.38, 0.30, 0.32])[0]


def _teeth(age: int) -> list[str]:
    if age < 6:
        return PRIMARY
    if age < 12:
        return PRIMARY[:10] + PERMANENT[2:14]
    return PERMANENT


def generate(patients: int, seed: int, personas: bool = True) -> Dataset:
    rng = random.Random(seed)
    fake = Faker("en_US")
    fake.seed_instance(seed)
    ds = Dataset()

    if personas:  # named personas first, each with a history fixed by its own id, whatever the seed
        from synthdata.personas import PERSONAS
        for p in PERSONAS:
            ds.patients.append(p)
            _history(ds, random.Random(p.id), p.id, p.age_on_anchor, p.home_location, p.deceased_at)

    for i in range(patients):
        mrn_no = FIRST_GENERATED_MRN + i
        pid = _id("patient", seed, i)
        age = min(92, max(1, int(rng.triangular(1, 92, 38))))
        dob = ANCHOR - timedelta(days=age * 365 + rng.randrange(365))
        sex = rng.choice(["female", "male"])
        given = fake.first_name_female() if sex == "female" else fake.first_name_male()
        family = fake.last_name()
        home = _home(age, rng)
        deceased = None
        if age > 60 and rng.random() < 0.01:
            deceased = datetime.combine(ANCHOR - timedelta(days=rng.randrange(30, 400)), time(12), tzinfo=timezone.utc)
        ds.patients.append(Patient(
            id=pid, mrn=f"NG{mrn_no:07d}", given_name=given, family_name=family, date_of_birth=dob,
            sex_at_birth=sex, home_location=home,
            email=f"{_ascii(given)}.{_ascii(family)}.{mrn_no}@patients.northgate.synthetic",
            phone=f"+1{rng.choice(['617', '781', '857'])}55501{rng.randrange(100):02d}",
            preferred_language="es" if rng.random() < 0.12 else "en",
            deceased_at=deceased, age_on_anchor=age,
        ))
        _history(ds, rng, pid, age, home, deceased)
    return ds


def _proc(ds, rng, pid, loc, code, enc, when, tooth=None, phase=None):
    status = "completed" if when else "planned"
    ds.procedures.append(Procedure(
        id=_id("procedure", pid, len(ds.procedures)), patient_id=pid, location=loc, service=code,
        performer=PERFORMER[loc][code], encounter_id=enc, plan_phase_id=phase, tooth=tooth,
        status=status, performed_at=when,
    ))


def _history(ds: Dataset, rng: random.Random, pid: str, age: int, home: str, deceased: datetime | None) -> None:
    """Eighteen months of six-monthly recalls, with treatment along the way, then perhaps a plan."""
    teeth = _teeth(age)
    end = deceased.date() if deceased else ANCHOR
    visit = ANCHOR - timedelta(days=540 + rng.randrange(60))
    while visit < end:
        if rng.random() < 0.8:  # most patients keep most recalls
            when = _at(visit, rng)
            enc = _id("encounter", pid, visit)
            ds.encounters.append(Encounter(id=enc, patient_id=pid, location=home,
                                           performer=PERFORMER[home]["D0150"], occurred_at=when, kind="exam"))
            _proc(ds, rng, pid, home, "D0150", enc, when)
            cleaning = "D1120" if age < 14 and "D1120" in OFFERED[home] else "D1110"
            _proc(ds, rng, pid, home, cleaning, enc, when)
            _treatment(ds, rng, pid, age, home, enc, when, teeth)
        visit += timedelta(days=180 + rng.randrange(-20, 21))

    if not deceased and rng.random() < 0.15:
        _plan(ds, rng, pid, age, home, teeth)


def _treatment(ds, rng, pid, age, home, enc, when, teeth):
    if rng.random() < 0.25:
        tooth = rng.choice(teeth)
        _proc(ds, rng, pid, home, "D2391", enc, when, tooth)
        ds.tooth_conditions.append(ToothCondition(id=_id("tooth", enc, tooth, "filled"), patient_id=pid,
                                                  encounter_id=enc, tooth=tooth, condition="filled", recorded_at=when))
    if "D7140" in OFFERED[home] and rng.random() < (0.10 if home == "quincy" else 0.04):
        tooth = rng.choice(teeth)
        _proc(ds, rng, pid, home, "D7140", enc, when, tooth)
        ds.tooth_conditions.append(ToothCondition(id=_id("tooth", enc, tooth, "missing"), patient_id=pid,
                                                  encounter_id=enc, tooth=tooth, condition="missing", recorded_at=when))
    if rng.random() < 0.10:
        tooth = rng.choice(teeth)
        ds.tooth_conditions.append(ToothCondition(id=_id("tooth", enc, tooth, "caries"), patient_id=pid,
                                                  encounter_id=enc, tooth=tooth, condition="caries", recorded_at=when))
    if home == "back-bay" and age >= 18 and rng.random() < 0.04:
        tooth = rng.choice(PERMANENT)
        _proc(ds, rng, pid, home, "D3330", enc, when, tooth)
        ds.tooth_conditions.append(ToothCondition(id=_id("tooth", enc, tooth, "root_canal"), patient_id=pid,
                                                  encounter_id=enc, tooth=tooth, condition="root_canal", recorded_at=when))
    if home == "back-bay" and age >= 25 and rng.random() < 0.03:  # E25: implants only where the CT scanner is
        tooth = rng.choice(PERMANENT)
        _proc(ds, rng, pid, home, "D6010", enc, when, tooth)
        ds.tooth_conditions.append(ToothCondition(id=_id("tooth", enc, tooth, "implant"), patient_id=pid,
                                                  encounter_id=enc, tooth=tooth, condition="implant", recorded_at=when))
    if home == "quincy" and age >= 55 and rng.random() < 0.05:
        _proc(ds, rng, pid, home, "D5110", enc, when)
    if home == "cambridge" and age >= 18 and rng.random() < 0.05:
        _proc(ds, rng, pid, home, "D9972", enc, when)
    if 11 <= age <= 17 and home in ("cambridge", "back-bay") and rng.random() < 0.06:
        _proc(ds, rng, pid, home, "D8090", enc, when)


def _plan(ds, rng, pid, age, home, teeth):
    created = datetime.combine(ANCHOR - timedelta(days=rng.randrange(1, 90)), time(15), tzinfo=timezone.utc)
    plan_id = _id("plan", pid)
    ds.plans.append(Plan(id=plan_id, patient_id=pid, location=home,
                         status=rng.choice(["proposed", "proposed", "accepted"]), created_at=created))
    options = [c for c in ("D2391", "D3330", "D6010", "D7140", "D5110", "D8090") if c in OFFERED[home]]
    for seq in (1, 2)[: rng.choice([1, 2])]:
        phase_id = _id("phase", plan_id, seq)
        ds.phases.append(Phase(id=phase_id, plan_id=plan_id, patient_id=pid, sequence=seq, name=f"Phase {seq}"))
        code = rng.choice(options)
        tooth = rng.choice(teeth) if code in ("D2391", "D3330", "D6010", "D7140") else None
        _proc(ds, rng, pid, home, code, None, None, tooth, phase_id)


# ---------------------------------------------------------------------------------------------- SQL

def _q(v) -> str:
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, (date, datetime)):
        return f"'{v.isoformat()}'"
    return "'" + str(v).replace("'", "''") + "'"


def _values(rows: list[list]) -> str:
    return ",\n".join("(" + ", ".join(_q(v) for v in r) + ")" for r in rows)


def _chunks(rows: list, size: int = 1000):
    for i in range(0, len(rows), size):
        yield rows[i:i + size]


def to_sql(ds: Dataset) -> str:
    """Idempotent SQL for the dataset. Locations, practitioners and fees are resolved inside the database."""
    from synthdata.personas import DR_CHEN_NAME, DR_CHEN_PROFILE
    out = ["-- Generated synthetic data. Describes no real person.", "begin;",
           f"update public.profiles set display_name = {_q(DR_CHEN_NAME)}"
           f" where id = {_q(DR_CHEN_PROFILE)} and display_name is distinct from {_q(DR_CHEN_NAME)};",
           f"update public.practitioners set display_name = {_q(DR_CHEN_NAME)}"
           f" where profile_id = {_q(DR_CHEN_PROFILE)} and display_name is distinct from {_q(DR_CHEN_NAME)};"]
    for chunk in _chunks(ds.patients):
        out.append(
            "insert into public.patients (id, mrn, given_name, family_name, date_of_birth, sex_at_birth, home_location_id,"
            " email, phone, preferred_language, deceased_at, is_synthetic, is_canary)\n"
            "select v.id::uuid, v.mrn, v.given, v.family, v.dob::date, v.sex, l.id, v.email, v.phone, v.lang,"
            " v.deceased::timestamptz, true, v.canary from (values\n"
            + _values([[p.id, p.mrn, p.given_name, p.family_name, p.date_of_birth, p.sex_at_birth, p.home_location,
                        p.email, p.phone, p.preferred_language, p.deceased_at, p.is_canary] for p in chunk])
            + "\n) as v(id, mrn, given, family, dob, sex, loc, email, phone, lang, deceased, canary)\n"
            "join public.locations l on l.code = v.loc\non conflict (id) do nothing;")
    for chunk in _chunks(ds.encounters):
        out.append(
            "insert into public.encounters (id, patient_id, location_id, practitioner_id, occurred_at, kind)\n"
            "select v.id::uuid, v.pid::uuid, l.id, pr.id, v.at::timestamptz, v.kind from (values\n"
            + _values([[e.id, e.patient_id, e.location, P[e.performer], e.occurred_at, e.kind] for e in chunk])
            + "\n) as v(id, pid, loc, prof, at, kind)\n"
            "join public.locations l on l.code = v.loc join public.practitioners pr on pr.profile_id = v.prof::uuid\n"
            "on conflict (id) do nothing;")
    for chunk in _chunks(ds.tooth_conditions):
        out.append(
            "insert into public.tooth_conditions (id, patient_id, encounter_id, tooth, condition, recorded_at)\n"
            "select v.id::uuid, v.pid::uuid, v.enc::uuid, v.tooth, v.cond, v.at::timestamptz from (values\n"
            + _values([[c.id, c.patient_id, c.encounter_id, c.tooth, c.condition, c.recorded_at] for c in chunk])
            + "\n) as v(id, pid, enc, tooth, cond, at)\non conflict (id) do nothing;")
    for chunk in _chunks(ds.plans):
        out.append(
            "insert into public.treatment_plans (id, patient_id, location_id, status, created_at)\n"
            "select v.id::uuid, v.pid::uuid, l.id, v.status, v.at::timestamptz from (values\n"
            + _values([[p.id, p.patient_id, p.location, p.status, p.created_at] for p in chunk])
            + "\n) as v(id, pid, loc, status, at)\njoin public.locations l on l.code = v.loc\non conflict (id) do nothing;")
    for chunk in _chunks(ds.phases):
        out.append(
            "insert into public.plan_phases (id, plan_id, patient_id, sequence, name)\n"
            "select v.id::uuid, v.plan::uuid, v.pid::uuid, v.seq, v.name from (values\n"
            + _values([[p.id, p.plan_id, p.patient_id, p.sequence, p.name] for p in chunk])
            + "\n) as v(id, plan, pid, seq, name)\non conflict (id) do nothing;")
    for chunk in _chunks(ds.procedures):
        out.append(
            "insert into public.dental_procedures (id, patient_id, location_id, service_id, practitioner_id, encounter_id,"
            " plan_phase_id, tooth, status, fee_cents, performed_at)\n"
            "select v.id::uuid, v.pid::uuid, ls.location_id, ls.service_id, pr.id, v.enc::uuid, v.phase::uuid, v.tooth,"
            " v.status, ls.price_cents, v.at::timestamptz from (values\n"
            + _values([[p.id, p.patient_id, p.location, p.service, P[p.performer], p.encounter_id, p.plan_phase_id,
                        p.tooth, p.status, p.performed_at] for p in chunk])
            + "\n) as v(id, pid, loc, code, prof, enc, phase, tooth, status, at)\n"
            "join public.locations l on l.code = v.loc join public.services s on s.code = v.code\n"
            "join public.location_services ls on ls.location_id = l.id and ls.service_id = s.id\n"
            "join public.practitioners pr on pr.profile_id = v.prof::uuid\non conflict (id) do nothing;")
    out.append("commit;")
    return "\n".join(out) + "\n"
