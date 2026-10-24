"""Find words the TTS voice misread, by comparing a Whisper transcript of the audio with the text."""

import re
from difflib import SequenceMatcher

MAX_SPAN = 3


def _tokens(text: str) -> list[str]:
    text = re.sub(r"['’]s\b", "", text.lower())  # "Dzoo's" compares as "dzoo"
    return re.findall(r"[a-z0-9]+", text.replace("’", "").replace("'", ""))


def misheard(expected: str, heard: str, ignore: set[str] = frozenset()) -> list[tuple[str, str]]:
    """(expected words, heard words) for each short stretch the transcript replaced."""
    a, b = _tokens(expected), _tokens(heard)
    out = []
    for op, i1, i2, j1, j2 in SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if op != "replace" or i2 - i1 > MAX_SPAN or j2 - j1 > MAX_SPAN:
            continue
        if all(t in ignore for t in a[i1:i2]):
            continue
        out.append((" ".join(a[i1:i2]), " ".join(b[j1:j2])))
    return out
