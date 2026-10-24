"""Whisper transcription through LiteLLM (never a local whisper)."""

import os
from dataclasses import dataclass, field
from pathlib import Path

import httpx

from .config import LITELLM_URL


@dataclass
class Segment:
    start: float
    end: float
    text: str
    avg_logprob: float | None = None
    no_speech_prob: float | None = None
    words: list[tuple[str, float, float]] = field(default_factory=list)


def parse_verbose(js: dict, offset_s: float = 0.0) -> list[Segment]:
    segments = []
    for s in js.get("segments") or []:
        words = [
            ((w.get("word") or w.get("text") or "").strip(), w["start"] + offset_s, w["end"] + offset_s)
            for w in s.get("words") or []
        ]
        segments.append(
            Segment(
                start=s["start"] + offset_s,
                end=s["end"] + offset_s,
                text=s["text"].strip(),
                avg_logprob=s.get("avg_logprob"),
                no_speech_prob=s.get("no_speech_prob"),
                words=words,
            )
        )
    return segments


def transcribe(path: Path, offset_s: float = 0.0, client: httpx.Client | None = None) -> list[Segment]:
    client = client or httpx.Client(timeout=600)
    with open(path, "rb") as f:
        resp = client.post(
            LITELLM_URL,
            headers={"Authorization": f"Bearer {os.environ['LITELLM_MASTER_KEY']}"},
            data={"model": "whisper", "response_format": "verbose_json", "timestamp_granularities[]": "word"},
            files={"file": (path.name, f, "audio/wav")},
        )
    resp.raise_for_status()
    return parse_verbose(resp.json(), offset_s)
