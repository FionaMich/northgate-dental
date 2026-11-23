"""The safety gate: runs before the model on every message. A red flag in any supported language skips the model and
returns the fixed emergency text (blueprint section 31: red-flag messages skip the model). Deliberately broad: a false
alarm costs a phone call; a missed one could cost much more. Patterns are draft for every language but English until a
native speaker reviews them."""

import re
from functools import cache
from pathlib import Path

import yaml

LANGUAGES = ("en", "fr", "nl", "de", "es", "lt", "sv")  # Fiona, 2026-11-23

# One or more patterns per flag per language; all of them run on every message, whatever language it is in.
_RED_FLAGS: dict[str, list[str]] = {
    "breathing_or_swallowing": [
        r"(can.?t|cannot|hard to|trouble|difficult\w*)\s+(breath|swallow)", r"choking",
        r"(du mal [àa]|n'arrive pas [àa]|ne peux pas)\s+(respirer|avaler)",
        r"(moeite met|kan niet)\s+(ademen|slikken)|benauwd",
        r"(kann nicht|schwer zu|probleme beim|schwierigkeiten beim)\s+(atmen|schlucken)|atemnot",
        r"(no puedo|dificultad para|me cuesta)\s+(respirar|tragar)",
        r"(sunku|negaliu)\s+(kvėpuoti|ryti)|dūstu",
        r"(svårt att|kan inte)\s+(andas|svälja)|andnöd",
    ],
    "heavy_bleeding": [
        r"bleed\w*.{0,30}(won.?t stop|not stop|heavy|a lot)",
        r"saign\w*.{0,30}(ne s'arr[êe]te pas|beaucoup)",
        r"bloed\w*.{0,30}(stopt niet|houdt niet op|veel|erg)",
        r"blut\w*.{0,30}(h[öo]rt nicht auf|stark|viel)",
        r"(sangrado|sangra).{0,30}(no (se )?(para|detiene)|mucho)",
        r"kraujav\w*.{0,30}(nesiliauja|nesustoja|stipr)",
        r"blöd\w*.{0,30}(slutar inte|kraftig|mycket)",
    ],
    "spreading_swelling": [
        r"swell\w*.{0,40}(eye|throat|neck|spread)",
        r"gonfl\w*.{0,40}([œo]eil|gorge|cou|s'[ée]tend)",
        r"zwel\w*.{0,40}(oog|keel|nek|verspreid)",
        r"schwell\w*.{0,40}(auge|hals|rachen|breitet)",
        r"hinchaz[oó]n.{0,40}(ojo|garganta|cuello|extiende)",
        r"tin\w*.{0,40}(akį|akies|gerkl|kakl|plinta)",
        r"svull\w*.{0,40}(öga|ögat|hals|sprider)",
    ],
    "chest_pain": [
        r"chest pain|pain in (my )?chest", r"douleur (à la|dans la) poitrine", r"pijn (op|in) de borst",
        r"brustschmerz|schmerzen in der brust", r"dolor (en el|de) pecho", r"skauda krūtin|krūtinės skausm",
        r"ont i bröstet|bröstsmärt",
    ],
    "self_harm": [
        r"(kill|hurt|harm)\w*\s+(myself|me)|suicid|end my life", r"(me tuer|me faire du mal|suicid)",
        r"(zelfmoord|mezelf (iets )?aandoen|een eind aan mijn leven)", r"(mich umbringen|mir etwas antun|suizid|selbstmord)",
        r"(matarme|hacerme daño|suicid)", r"(nusižudyti|save sužaloti|savižudyb)", r"(ta livet av mig|skada mig själv|självmord)",
    ],
}
_COMPILED = {flag: [re.compile(p, re.IGNORECASE) for p in patterns] for flag, patterns in _RED_FLAGS.items()}


def red_flags(message: str) -> list[str]:
    """Every red flag in the message, in any supported language. Empty when there is none."""
    return sorted(flag for flag, patterns in _COMPILED.items() if any(p.search(message) for p in patterns))


@cache
def texts() -> dict:
    return yaml.safe_load((Path(__file__).parent / "texts" / "fixed.yaml").read_text())


def fixed(key: str, language: str, phone: str | None = None) -> str:
    """A reviewed, never-generated text in the patient's language (English if the language is unknown)."""
    table = texts()
    entry = table.get(language) or table["en"]
    return entry[key].replace("{phone}", phone or "your clinic")
