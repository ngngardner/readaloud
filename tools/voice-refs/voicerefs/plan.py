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
    return [{"text": piece, "spoken": apply_names(piece, name_map), "voice": f"{CONTAINER_VOICES}/{clip.file}",
             "reference_text": clip.transcript}
            for clip, text in runs for piece in chunk(text, MAX_CHARS)]


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
    """Respellings for pinyin names not seen before. A name that also appears in lowercase ("long") is an
    English word, and respelling it would change ordinary prose."""
    out = {}
    for name in (n.strip() for n in found):
        if not name or name in existing or name not in text:
            continue
        if " " not in name and re.search(rf"\b{re.escape(name.lower())}\b", text):
            continue
        spelled = names.respell(name)
        if spelled is not None:
            out[name] = spelled
    return out
