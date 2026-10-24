"""Breeze generation through LocalAI, per passage and method."""

import io
import json
import re
import subprocess
import tempfile
import time
from dataclasses import asdict
from pathlib import Path
from typing import Callable

import httpx
import numpy as np
import soundfile as sf

from . import audio
from .chapter import Passage
from .config import BREEZE_URL, CONTAINER_VOICES, FALLBACK_REF, MAX_CHARS, SAMPLE_RATE, TARGET_DBFS
from .library import RefClip, pick
from .names import apply_names
from .textunits import chunk

METHODS = ["current", "matched", "matched_names"]
ATTEMPTS = 3
GAP_S = 0.12

Synth = Callable[[str, str, str], np.ndarray]


class TTSFailed(Exception):
    pass


def speak(text: str, ref_file: str, ref_text: str, client: httpx.Client | None = None,
          backoff_s: float = 5.0) -> np.ndarray:
    client = client or httpx.Client(timeout=300)
    body = {
        "model": "breeze-tts-2",
        "input": text,
        "voice": f"{CONTAINER_VOICES}/{ref_file}",
        "params": {"reference_text": ref_text, "seed": "42", "text_chunk_size": "2000"},
    }
    error = "no attempt"
    for attempt in range(ATTEMPTS):
        try:
            resp = client.post(BREEZE_URL, json=body)
            if resp.status_code == 200:
                samples, rate = sf.read(io.BytesIO(resp.content), dtype="float64", always_2d=False)
                if rate != SAMPLE_RATE:
                    raise TTSFailed(f"unexpected sample rate {rate}")
                return samples
            error = f"HTTP {resp.status_code}: {resp.text[:200]}"
        except httpx.HTTPError as exc:
            error = f"{type(exc).__name__}: {exc}"
        time.sleep(backoff_s * (attempt + 1))
    raise TTSFailed(error)


def render(text: str, ref_file: str, ref_text: str, client: httpx.Client | None = None) -> np.ndarray:
    client = client or httpx.Client(timeout=300)
    gap = np.zeros(int(SAMPLE_RATE * GAP_S))
    parts: list[np.ndarray] = []
    for piece in chunk(text, MAX_CHARS):
        if parts:
            parts.append(gap)
        parts.append(audio.level(speak(piece, ref_file, ref_text, client), TARGET_DBFS))
    return np.concatenate(parts) if parts else np.zeros(0)


def encode_opus(samples: np.ndarray, out: Path) -> Path:
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        audio.write(Path(tmp.name), samples, SAMPLE_RATE)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp.name, "-c:a", "libopus", "-b:a", "48k", str(out)],
                       check=True)
    return out


def _fresh(out: Path, signature: dict) -> bool:
    """The output exists and was made from exactly this text and reference clip."""
    sidecar = out.with_suffix(".json")
    try:
        return out.exists() and json.loads(sidecar.read_text()) == signature
    except (OSError, json.JSONDecodeError):
        return False


def _render_to(out: Path, signature: dict, synth: Synth, text: str, ref_file: str, ref_text: str) -> None:
    encode_opus(synth(text, ref_file, ref_text), out)
    out.with_suffix(".json").write_text(json.dumps(signature))


CURRENT_REF = RefClip("current", FALLBACK_REF[0], FALLBACK_REF[1], "narrator", 0.0, 0.0)


def _plan(passage: Passage, lib: dict, name_map: dict[str, str]) -> dict[str, tuple[str, RefClip]]:
    matched = pick(lib, passage.cluster or passage.category)
    return {
        "current": (passage.text, CURRENT_REF),
        "matched": (passage.text, matched),
        "matched_names": (apply_names(passage.text, name_map), matched),
    }


def generate(passages: list[Passage], lib: dict[str, list[RefClip]], name_map: dict[str, str], out_dir: Path,
             synth: Synth | None = None, methods: list[str] = METHODS) -> dict:
    synth = synth or render
    out_dir.mkdir(parents=True, exist_ok=True)
    result: dict[str, dict] = {}
    for p in passages:
        result[str(p.idx)] = {}
        for method, (text, ref) in _plan(p, lib, name_map).items():
            if method not in methods:
                continue
            name = f"{p.idx:03d}-{method}.opus"
            record = {"text": text, "ref": asdict(ref)}
            signature = {"text": text, "ref_file": ref.file, "ref_text": ref.transcript}
            if not _fresh(out_dir / name, signature):
                try:
                    _render_to(out_dir / name, signature, synth, text, ref.file, ref.transcript)
                except TTSFailed as exc:
                    record["failed"] = str(exc)
                    print(f"passage {p.idx} {method}: FAILED {exc}", flush=True)
            if "failed" not in record:
                record["file"] = name
            result[str(p.idx)][method] = record
        print(f"passage {p.idx} done", flush=True)
    return result


def generate_names(entries: dict[str, dict], out_dir: Path, synth: Synth | None = None) -> dict[str, dict[str, str]]:
    synth = synth or render
    out_dir.mkdir(parents=True, exist_ok=True)
    out: dict[str, dict[str, str]] = {}
    for name, e in entries.items():
        forms = {"original": name, "respelling": e.get("respelling", ""), "hanzi": e.get("hanzi", "")}
        slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
        out[name] = {}
        for form, spoken in forms.items():
            if not spoken:
                continue
            file = f"name-{slug}-{form}.opus"
            sentence = f"{spoken} nodded slowly."
            signature = {"text": sentence, "ref_file": FALLBACK_REF[0], "ref_text": FALLBACK_REF[1]}
            if not _fresh(out_dir / file, signature):
                try:
                    _render_to(out_dir / file, signature, synth, sentence, *FALLBACK_REF)
                except TTSFailed as exc:
                    print(f"name {name} {form}: FAILED {exc}", flush=True)
                    continue
            out[name][form] = file
    return out
