"""Per-book name pronunciation: pinyin parsing, English respelling, substitution."""

import re
from functools import lru_cache

INITIALS = {
    "zh": "j", "ch": "ch", "sh": "sh", "b": "b", "p": "p", "m": "m", "f": "f", "d": "d", "t": "t",
    "n": "n", "l": "l", "g": "g", "k": "k", "h": "h", "j": "j", "q": "ch", "x": "sh", "r": "r",
    "z": "dz", "c": "ts", "s": "s",
}
FINALS = {
    "a": "ah", "o": "aw", "e": "uh", "ai": "ye", "ei": "ay", "ao": "ow", "ou": "oh", "an": "ahn",
    "en": "un", "ang": "ahng", "eng": "ung", "ong": "ong", "i": "ee", "ia": "yah", "ie": "yeh",
    "iao": "yow", "iu": "yo", "ian": "yen", "in": "een", "iang": "yahng", "ing": "ing", "iong": "yong",
    "u": "oo", "ua": "wah", "uo": "waw", "uai": "wye", "ui": "way", "uan": "wahn", "un": "wun",
    "uang": "wahng", "ue": "yweh", "ü": "yoo", "üe": "yweh", "üan": "yoo-en", "ün": "yoon",
}
# After j/q/x a written "u" is ü.
JQX_FINALS = {"u": "yoo", "ue": "weh", "uan": "wen", "un": "yoon"}
APICAL = {"zh": "r", "ch": "r", "sh": "r", "r": "r", "z": "uh", "c": "uh", "s": "uh"}
WHOLE = {
    "ya": "yah", "ye": "yeh", "yao": "yow", "you": "yoh", "yan": "yen", "yin": "yeen", "yang": "yahng",
    "ying": "ying", "yong": "yong", "yu": "yoo", "yue": "yweh", "yuan": "yoo-en", "yun": "yoon",
    "yi": "ee", "wa": "wah", "wo": "waw", "wai": "wye", "wei": "way", "wan": "wahn", "wen": "wun",
    "wang": "wahng", "weng": "wung", "wu": "woo",
    "a": "ah", "o": "aw", "e": "uh", "ai": "eye", "ei": "ay", "ao": "ow", "ou": "oh", "an": "ahn",
    "en": "un", "ang": "ahng", "eng": "ung", "er": "ar",
}


def _respell_syllable(syl: str) -> str | None:
    if syl in WHOLE:
        return WHOLE[syl]
    for ini in sorted(INITIALS, key=len, reverse=True):
        if syl.startswith(ini):
            fin = syl[len(ini):]
            if fin == "i" and ini in APICAL:
                return INITIALS[ini] + APICAL[ini]
            if ini in ("j", "q", "x") and fin in JQX_FINALS:
                return INITIALS[ini] + JQX_FINALS[fin]
            if fin in FINALS:
                return INITIALS[ini] + FINALS[fin]
            return None
    return None


@lru_cache(maxsize=None)
def _parse_word(word: str) -> tuple[str, ...] | None:
    if not word:
        return ()
    for n in range(min(6, len(word)), 0, -1):
        head = word[:n]
        if _respell_syllable(head) is not None:
            rest = _parse_word(word[n:])
            if rest is not None:
                return (head,) + rest
    return None


def _words(name: str) -> list[str]:
    return name.lower().replace("v", "ü").split()


def syllables(name: str) -> list[str] | None:
    out: list[str] = []
    for word in _words(name):
        parsed = _parse_word(word)
        if parsed is None:
            return None
        out.extend(parsed)
    return out or None


def respell(name: str) -> str | None:
    words = []
    for word in _words(name):
        parsed = _parse_word(word)
        if parsed is None:
            return None
        spelled = "".join(_respell_syllable(s) for s in parsed)
        words.append(spelled[0].upper() + spelled[1:])
    return " ".join(words) or None


def hanzi_matches(name: str, hanzi: str) -> bool:
    from pypinyin import Style, pinyin

    syls = syllables(name)
    readings = pinyin(hanzi, style=Style.NORMAL, heteronym=True, v_to_u=True)
    if syls is None or len(readings) != len(syls):
        return False
    return all(s in options for s, options in zip(syls, readings))


def apply_names(text: str, mapping: dict[str, str]) -> str:
    if not mapping:
        return text
    keys = sorted(mapping, key=len, reverse=True)
    pattern = re.compile(r"\b(" + "|".join(re.escape(k) for k in keys) + r")\b")
    return pattern.sub(lambda m: mapping[m.group(1)], text)
