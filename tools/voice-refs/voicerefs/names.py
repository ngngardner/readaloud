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


# Other English spellings to try for sounds a TTS voice may misread (default spelling first in the tables above).
FINAL_ALTS = {"e": ["ur", "uhh"], "eng": ["uhng"], "en": ["en"], "ou": ["oe"], "iu": ["yoh"], "ui": ["whey"],
              "ie": ["yeah"], "uo": ["woh"], "ian": ["yan"], "in": ["in"], "ai": ["igh"], "ang": ["ung"]}
WHOLE_ALTS = {"er": ["er", "arr"], "e": ["ur"], "you": ["yo"], "yi": ["yee"], "ai": ["i"], "en": ["en"]}
APICAL_ALTS = {"r": ["ruh"], "uh": ["z"]}


def _syllable_options(syl: str) -> list[str]:
    """Spellings for one pinyin syllable: the default respelling first, then alternatives."""
    base = _respell_syllable(syl)
    if base is None:
        return []
    if syl in WHOLE:
        alts = WHOLE_ALTS.get(syl, [])
    else:
        ini = next(i for i in sorted(INITIALS, key=len, reverse=True) if syl.startswith(i))
        fin = syl[len(ini):]
        if fin == "i" and ini in APICAL:
            alts = [INITIALS[ini] + a for a in APICAL_ALTS[APICAL[ini]]]
        elif ini in ("j", "q", "x") and fin in JQX_FINALS:
            alts = []
        else:
            alts = [INITIALS[ini] + a for a in FINAL_ALTS.get(fin, [])]
    return [base] + [a for a in alts if a != base]


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


def _cap(word: str) -> str:
    return word[0].upper() + word[1:]


def _options(name: str) -> list[list[list[str]]] | None:
    words = [_parse_word(w) for w in _words(name)]
    if not words or any(w is None for w in words):
        return None
    return [[_syllable_options(s) for s in w] for w in words]


def _spell(choice: list[list[str]]) -> str:
    return " ".join(_cap("".join(w)) for w in choice)


def respell_variants(name: str) -> list[str]:
    """The default respelling, then the same with one syllable at a time swapped for an alternative."""
    options = _options(name)
    if options is None:
        return []
    base = [[o[0] for o in w] for w in options]
    out = [_spell(base)]
    for wi, w in enumerate(options):
        for si, opts in enumerate(w):
            for alt in opts[1:]:
                choice = [list(x) for x in base]
                choice[wi][si] = alt
                if _spell(choice) not in out:
                    out.append(_spell(choice))
    return out


def combine_best(name: str, scores: dict[str, float]) -> str:
    """Per syllable, keep the alternative whose one-syllable variant scored best (ties keep the default)."""
    options = _options(name)
    base = [[o[0] for o in w] for w in options]
    base_score = scores.get(_spell(base), 0.0)
    chosen = [list(x) for x in base]
    for wi, w in enumerate(options):
        for si, opts in enumerate(w):
            best, best_score = opts[0], base_score
            for alt in opts[1:]:
                trial = [list(x) for x in base]
                trial[wi][si] = alt
                if scores.get(_spell(trial), -1.0) > best_score:
                    best, best_score = alt, scores[_spell(trial)]
            chosen[wi][si] = best
    return _spell(chosen)


def _letters(text: str) -> str:
    return re.sub(r"[^a-z]", "", text.lower())


def score_heard(heard: str, candidate: str, pinyin_name: str) -> float:
    """How well a transcript of "<candidate> nodded slowly." matches either the spelling or the pinyin."""
    from difflib import SequenceMatcher

    said = _letters(" ".join(heard.split()[: len(candidate.split())]))
    return max(SequenceMatcher(None, said, _letters(candidate)).ratio(),
               SequenceMatcher(None, said, _letters(pinyin_name)).ratio())


def hanzi_matches(name: str, hanzi: str) -> bool:
    from pypinyin import Style, pinyin

    syls = syllables(name)
    readings = pinyin(hanzi, style=Style.NORMAL, heteronym=True, v_to_u=True)
    if syls is None or len(readings) != len(syls):
        return False
    return all(s in options for s, options in zip(syls, readings))


def apply_names(text: str, mapping: dict[str, str]) -> str:
    """Names (capitalised keys) match exactly; lowercase keys are word fixes that match any case."""
    if not mapping:
        return text
    keys = sorted(mapping, key=len, reverse=True)
    pattern = re.compile(r"\b(" + "|".join(f"(?i:{re.escape(k)})" if k.islower() else re.escape(k) for k in keys) + r")\b")

    def sub(m: re.Match) -> str:
        found = m.group(1)
        if found in mapping:
            return mapping[found]
        fix = mapping[found.lower()]
        return fix[0].upper() + fix[1:] if found[0].isupper() else fix

    return pattern.sub(sub, text)
