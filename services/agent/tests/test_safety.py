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
    ("lt", "Man sunku kvėpuoti", "breathing_or_swallowing"),
    ("sv", "Jag har ont i bröstet", "chest_pain"),
    ("de", "Ich will mich umbringen", "self_harm"),
    ("en", "Sometimes I want to end my life", "self_harm"),
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
    assert fixed("disclosure", "xx").startswith("Hi, I'm Northgate Dental's virtual receptionist")
