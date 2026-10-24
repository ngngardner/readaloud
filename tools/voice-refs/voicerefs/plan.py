"""Voice plans for readaloud: each chapter as chunks, each chunk with its own narrator clip and respelled names.

The steps are the ones the comparison page was made with (`voicerefs chapter` + `match`), run per chapter and
handed to readaloud instead of rendered here. See ReadaloudAudiobook.VoicePlan for the format readaloud reads.
"""

import re

from . import names
from .chapter import Passage
from .config import CONTAINER_VOICES, MAX_CHARS
from .library import RefClip, pick
from .names import apply_names
from .textunits import chunk

MODEL, VOICE = "breeze-tts-2", "heath-miller"


def chunks_for(passages: list[Passage], lib: dict[str, list[RefClip]], name_map: dict[str, str]) -> list[dict]:
    """One request per run of neighbouring passages that share a clip, cut at MAX_CHARS like readaloud cuts."""
    runs: list[tuple[RefClip, str]] = []
    for p in passages:
        clip = pick(lib, p.cluster or p.category)
        text = p.text.strip()
        if not text:
            continue
        if runs and runs[-1][0] == clip and len(runs[-1][1]) + 1 + len(text) <= MAX_CHARS:
            runs[-1] = (clip, runs[-1][1] + "\n" + text)
        else:
            runs.append((clip, text))
    pieces = _fold_wordless([(clip, piece) for clip, text in runs for piece in chunk(text, MAX_CHARS)])
    return [{"text": piece, "spoken": apply_names(piece, name_map), "voice": f"{CONTAINER_VOICES}/{clip.file}",
             "reference_text": clip.transcript}
            for clip, piece in pieces]


def _fold_wordless(pieces: list[tuple[RefClip, str]]) -> list[tuple[RefClip, str]]:
    """A piece with no words ("***", a silent "……") joins the piece before it, or the first one after it:
    Breeze can fail on a request with nothing to say."""
    out: list[tuple[RefClip, str]] = []
    pending = ""
    for clip, text in pieces:
        if not re.search(r"\w", text):
            if out:
                out[-1] = (out[-1][0], out[-1][1] + "\n" + text)
            else:
                pending += text + "\n"
            continue
        out.append((clip, pending + text))
        pending = ""
    return out


def document(passages: list[Passage], lib: dict[str, list[RefClip]], name_map: dict[str, str],
             temperature: float | None) -> dict:
    return {"model": MODEL, "voice": VOICE, "temperature": temperature,
            "chunks": chunks_for(passages, lib, name_map)}


def remember_speakers(tags: list[dict], picks: list[str | None], memory: dict[str, str],
                      groups: dict[str, str]) -> list[str | None]:
    """A character keeps the voice they were first given, across chapters, while it is of the right group.
    `memory` (speaker -> cluster) is updated in place with this chapter's new speakers."""
    out = []
    for tag, p in zip(tags, picks):
        if tag["kind"] != "dialogue" or p is None:
            out.append(p)
            continue
        kept = memory.get(tag["speaker"])
        if kept is not None and groups.get(kept) == groups.get(p):
            out.append(kept)
        else:
            memory[tag["speaker"]] = p
            out.append(p)
    return out


def new_names(found: list[str], text: str, existing: dict[str, str]) -> dict[str, str]:
    """Respellings for pinyin names of two or more words not seen before. Learned names apply to the whole book,
    and a one-word name ("Long", "Men") is too often an English word: respelling it would change ordinary prose."""
    out = {}
    for name in (n.strip() for n in found):
        if " " not in name or name in existing or name not in text:
            continue
        spelled = names.respell(name)
        if spelled is not None:
            out[name] = spelled
    return out


NAMES_SCHEMA = {
    "type": "object",
    # The cap ends a reply that starts repeating itself before it runs into max_tokens.
    "properties": {"names": {"type": "array", "items": {"type": "string"}, "maxItems": 60}},
    "required": ["names"],
}
NAMES_SYSTEM = """You prepare a pronunciation list for a narrator reading a Chinese web novel in English translation.
List every Chinese name written in pinyin in the text: people, nicknames, clans, tribes and places, exactly as written (e.g. "Hei Lou Lan", "Fang Yuan", "Huang Er"). Skip anything translated into English, such as "Blazing Heaven Demoness", "Verdant Great Sun" or "Spirit Affinity House". List each name once."""


def find_names(text: str, chat=None) -> list[str]:
    """Pinyin names in a chapter, asked of bonsai. A bad reply is retried once; a second one gives no names
    rather than failing the chapter, which then just uses the names already learned."""
    from . import bonsai

    chat = chat or bonsai.chat_json
    for _attempt in range(2):
        try:
            return [str(n) for n in chat(NAMES_SYSTEM, text, NAMES_SCHEMA)["names"]]
        except (ValueError, KeyError, TypeError):
            continue
    return []
