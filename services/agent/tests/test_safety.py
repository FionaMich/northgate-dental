"""The safety gate must catch emergencies in every supported language and leave ordinary dental questions alone."""
import pytest

from agent.safety import LANGUAGES, fixed, red_flags, texts

EMERGENCIES = [
    ("en", "My face is swollen and the swelling is spreading to my eye", "spreading_swelling"),
    ("en", "I can't breathe properly since the extraction", "breathing_or_swallowing"),
    ("fr", "J'ai du mal à respirer", "breathing_or_swallowing"),
    ("nl", "Het bloeden stopt niet sinds gisteren", "heavy_bleeding"),
    ("de", "Die Schwellung breitet sich zum Auge aus", "spreading_swelling"),
    ("es", "El sangrado no se detiene desde ayer", "heavy_bleeding"),
    ("it", "Il sanguinamento non si ferma", "heavy_bleeding"),
    ("it", "Non riesco a respirare bene", "breathing_or_swallowing"),
    ("lt", "Man sunku kvėpuoti", "breathing_or_swallowing"),
    ("sv", "Jag har ont i bröstet", "chest_pain"),
    ("de", "Ich will mich umbringen", "self_harm"),
    ("en", "Sometimes I want to end my life", "self_harm"),
    # heavy bleeding said the other way round, in every language
    ("en", "My mouth won't stop bleeding after my extraction", "heavy_bleeding"),
    ("en", "It has not stopped bleeding since this morning", "heavy_bleeding"),
    ("fr", "Ma bouche ne s'arrête pas de saigner", "heavy_bleeding"),
    ("nl", "Mijn tandvlees blijft maar bloeden", "heavy_bleeding"),
    ("de", "Es hört nicht auf zu bluten", "heavy_bleeding"),
    ("es", "No para de sangrar desde la extracción", "heavy_bleeding"),
    ("it", "La gengiva non smette di sanguinare", "heavy_bleeding"),
    ("lt", "Žaizda nesiliauja kraujuoti", "heavy_bleeding"),
    ("sv", "Det slutar inte blöda", "heavy_bleeding"),
]


@pytest.mark.parametrize("language,message,flag", EMERGENCIES)
def test_emergencies_are_caught_in_every_language(language, message, flag):
    assert flag in red_flags(message), f"{language}: {message}"


@pytest.mark.parametrize("message", [
    "Can I book a cleaning next Tuesday?",
    "¿Cuánto cuesta un blanqueamiento?",
    "Ik wil mijn afspraak verzetten",
    "Ich möchte einen Termin zur Zahnreinigung",
    "Noriu užsiregistruoti vizitui",
    "Kan jag boka en tid på fredag?",
    "Vorrei prenotare una pulizia dei denti",
    "Est-ce que je peux payer dans l'application ?",
    "My gums bled a little when I flossed",
])
def test_ordinary_questions_are_not_flagged(message):
    assert red_flags(message) == []


def test_every_language_has_every_fixed_text():
    table = texts()
    for language in LANGUAGES:
        for key in ("disclosure", "emergency", "cannot_advise", "handover"):
            assert table[language][key], f"{language} {key}"


def test_the_emergency_text_names_911_and_988_in_every_language():
    for language in LANGUAGES:
        text = fixed("emergency", language, "(617) 555-0130")
        assert "911" in text and "988" in text and "(617) 555-0130" in text, language


def test_unknown_languages_fall_back_to_english():
    assert fixed("disclosure", "xx").startswith("Hi, I'm Nora")


def test_nora_introduces_herself_as_an_ai_in_every_language():
    words = {"en": "AI", "fr": "intelligence artificielle", "nl": "AI", "de": "KI", "es": "inteligencia artificial",
             "it": "intelligenza artificiale", "lt": "dirbtinio intelekto", "sv": "AI"}
    for language in LANGUAGES:
        text = fixed("disclosure", language)
        assert "Nora" in text and words[language] in text, language
