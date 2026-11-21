"""The safety gate must catch emergencies in every supported language and leave ordinary dental questions alone."""
import pytest

from agent.safety import LANGUAGES, fixed, red_flags, texts

EMERGENCIES = [
    ("en", "My face is swollen and the swelling is spreading to my eye", "spreading_swelling"),
    ("en", "I can't breathe properly since the extraction", "breathing_or_swallowing"),
    ("es", "El sangrado no se detiene desde ayer", "heavy_bleeding"),
    ("pt", "Tenho dificuldade para engolir", "breathing_or_swallowing"),
    ("ht", "Senyen an pa sispann", "heavy_bleeding"),
    ("zh-Hans", "我吞咽困难", "breathing_or_swallowing"),
    ("zh-Hant", "腫脹蔓延到眼睛", "spreading_swelling"),
    ("vi", "Tôi bị đau ngực", "chest_pain"),
    ("ar", "عندي نزيف لا يتوقف", "heavy_bleeding"),
    ("fr", "J'ai du mal à respirer", "breathing_or_swallowing"),
    ("ru", "Кровотечение не останавливается", "heavy_bleeding"),
    ("ko", "자해하고 싶어요", "self_harm"),
    ("tl", "Hirap akong huminga", "breathing_or_swallowing"),
    ("en", "Sometimes I want to end my life", "self_harm"),
]


@pytest.mark.parametrize("language,message,flag", EMERGENCIES)
def test_emergencies_are_caught_in_every_language(language, message, flag):
    assert flag in red_flags(message), f"{language}: {message}"


@pytest.mark.parametrize("message", [
    "Can I book a cleaning next Tuesday?",
    "¿Cuánto cuesta un blanqueamiento?",
    "Mwen vle chanje randevou mwen",
    "我想预约洗牙",
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
