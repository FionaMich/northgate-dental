"""The safety gate: runs before the model on every message. A red flag in any supported language skips the model and
returns the fixed emergency text (blueprint section 31: red-flag messages skip the model). Deliberately broad: a false
alarm costs a phone call; a missed one could cost much more. Patterns are draft for every language but English until a
native speaker reviews them."""

import re
from functools import cache
from pathlib import Path

import yaml

LANGUAGES = ("en", "es", "pt", "ht", "zh-Hans", "zh-Hant", "vi", "ar", "fr", "ru", "ko", "tl")

# One pattern per flag per language; all of them run on every message, whatever language it is in.
_RED_FLAGS: dict[str, list[str]] = {
    "breathing_or_swallowing": [
        r"(can.?t|cannot|hard to|trouble|difficult\w*)\s+(breath|swallow)", r"choking",
        r"(no puedo|dificultad para|me cuesta)\s+(respirar|tragar)", r"(n[aã]o consigo|dificuldade (para|de))\s+(respirar|engolir)",
        r"(pa ka|difikilte pou)\s+(respire|vale)", r"(呼吸|吞咽|吞嚥)困难|(呼吸|吞咽|吞嚥)困難", r"khó (thở|nuốt)",
        r"صعوبة في (التنفس|البلع)|لا أستطيع (التنفس|البلع)", r"(du mal [àa]|n'arrive pas [àa]|ne peux pas)\s+(respirer|avaler)",
        r"(трудно|не могу)\s+(дышать|глотать)", r"(숨쉬기|삼키기|숨을 쉬기|삼키기가)\s*(어렵|힘들)", r"(hirap|hindi makahinga|hindi makalunok)",
    ],
    "heavy_bleeding": [
        r"bleed\w*.{0,30}(won.?t stop|not stop|heavy|a lot)", r"(sangrado|sangra).{0,30}(no (se )?(para|detiene)|mucho)",
        r"(sangramento|sangrando|sangra).{0,30}(n[aã]o para|muito)", r"senyen.{0,30}(pa sispann|anpil)", r"(出血|流血).{0,10}(止不住|不停)",
        r"chảy máu.{0,20}(không (cầm|ngừng)|nhiều)", r"نزيف.{0,20}(لا يتوقف|شديد)", r"saign\w*.{0,30}(ne s'arr[êe]te pas|beaucoup)",
        r"кровотечение.{0,30}(не останавливается|сильное)|кровь не останавливается", r"(피가|출혈).{0,10}(멈추지|안 멈)", r"(pagdurugo|dumudugo).{0,30}(hindi tumitigil|marami)",
    ],
    "spreading_swelling": [
        r"swell\w*.{0,40}(eye|throat|neck|spread)", r"hinchaz[oó]n.{0,40}(ojo|garganta|cuello|extiende)",
        r"incha\w*.{0,40}(olho|garganta|pesco[cç]o|espalha)", r"anfle\w*.{0,40}(je|gòj|kou|gaye)", r"肿.{0,10}(眼|喉|脖子|蔓延)|腫.{0,10}(眼|喉|脖子|蔓延)",
        r"sưng.{0,30}(mắt|cổ họng|cổ|lan)", r"تورم.{0,30}(العين|الحلق|الرقبة|يمتد)", r"gonfl\w*.{0,40}([œo]eil|gorge|cou|s'[ée]tend)",
        r"от[её]к.{0,40}(глаз|горл|ше[ия]|распространя)", r"(붓기|부기|부어).{0,20}(눈|목|퍼)", r"(maga|pamamaga).{0,40}(mata|lalamunan|leeg|kumakalat)",
    ],
    "chest_pain": [
        r"chest pain|pain in (my )?chest", r"dolor (en el|de) pecho", r"dor no peito", r"doulè nan pwatrin", r"胸痛|胸口痛",
        r"đau ngực", r"ألم في الصدر", r"douleur (à la|dans la) poitrine", r"боль в груди", r"가슴 통증|가슴이 아파", r"sakit sa dibdib",
    ],
    "self_harm": [
        r"(kill|hurt|harm)\w*\s+(myself|me)|suicid|end my life", r"(matarme|hacerme daño|suicid)", r"(me matar|me machucar|suic[ií]d)",
        r"(touye tèt mwen|fè tèt mwen mal)", r"自杀|自殺|伤害自己|傷害自己", r"tự tử|tự làm hại", r"(أقتل نفسي|انتحار|أؤذي نفسي)",
        r"(me tuer|me faire du mal|suicid)", r"(убить себя|покончить с собой|суицид|навредить себе)", r"(자살|죽고 싶|자해)",
        r"(magpakamatay|saktan ang sarili)",
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
