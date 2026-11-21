"""Load the named personas from personas.yaml as validated Patient records with fixed ids."""

from pathlib import Path

import yaml

from synthdata.generate import ANCHOR, Patient

# Dr Chen is the seeded orthodontist (profile ...011); the persona file names her.
DR_CHEN_PROFILE = "10000000-0000-4000-8000-000000000011"
DR_CHEN_NAME = "Dr Mei Chen (orthodontist)"


def _age(dob) -> int:
    return ANCHOR.year - dob.year - ((ANCHOR.month, ANCHOR.day) < (dob.month, dob.day))


def _load() -> list[Patient]:
    rows = yaml.safe_load(Path(__file__).with_name("personas.yaml").read_text())
    out = []
    for r in rows:
        number = int(r["mrn"][2:])
        out.append(Patient(
            id=r["id"], mrn=r["mrn"], given_name=r["given_name"], family_name=r["family_name"],
            date_of_birth=r["date_of_birth"], sex_at_birth=r["sex_at_birth"], home_location=r["home_location"],
            email=r.get("email") or f"{r['given_name'].lower()}.{r['family_name'].lower()}.{number}@personas.northgate.synthetic",
            phone=r.get("phone") or f"+1617555{number + 100:04d}",
            preferred_language=r["preferred_language"], is_canary=r.get("is_canary", False),
            age_on_anchor=_age(r["date_of_birth"]),
        ))
    return out


PERSONAS = _load()
