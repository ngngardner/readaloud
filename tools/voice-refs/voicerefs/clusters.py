"""Cluster the narrator's source segments by how they sound, then label and match clusters with bonsai."""

import json
from functools import lru_cache

import httpx
import numpy as np

from . import bonsai

ECAPA_DIMS = 16
PROSODY_WEIGHT = 2.0
ECAPA_RATE = 16000


def prosody(samples: np.ndarray, rate: int) -> np.ndarray:
    """[median F0 (semitones re 100 Hz), F0 interquartile range (st), RMS dBFS, voiced fraction]."""
    import parselmouth

    pitch = parselmouth.Sound(samples.astype(np.float64), sampling_frequency=rate).to_pitch(pitch_floor=60, pitch_ceiling=500)
    f0 = pitch.selected_array["frequency"]
    voiced = f0[f0 > 0]
    if len(voiced) == 0:
        st_med = st_iqr = 0.0
    else:
        st = 12 * np.log2(voiced / 100.0)
        st_med = float(np.median(st))
        st_iqr = float(np.percentile(st, 75) - np.percentile(st, 25))
    rms = float(np.sqrt(np.mean(np.square(samples)))) or 1e-9
    return np.array([st_med, st_iqr, 20 * np.log10(rms), len(voiced) / max(1, len(f0))])


@lru_cache(maxsize=1)
def _ecapa():
    from speechbrain.inference.speaker import EncoderClassifier

    from .config import WORK_DIR

    return EncoderClassifier.from_hparams(source="speechbrain/spkrec-ecapa-voxceleb",
                                          savedir=str(WORK_DIR / "models" / "ecapa"), run_opts={"device": "cpu"})


def embed(samples: np.ndarray, rate: int) -> np.ndarray:
    import torch
    from scipy.signal import resample_poly

    if rate != ECAPA_RATE:
        samples = resample_poly(samples, ECAPA_RATE, rate)
    with torch.no_grad():
        return _ecapa().encode_batch(torch.tensor(samples[None, :], dtype=torch.float32))[0, 0].numpy()


def _z(a: np.ndarray) -> np.ndarray:
    sd = a.std(axis=0)
    return (a - a.mean(axis=0)) / np.where(sd > 0, sd, 1)


def feature_matrix(emb: np.ndarray, pros: np.ndarray) -> np.ndarray:
    from sklearn.decomposition import PCA

    emb = emb / np.linalg.norm(emb, axis=1, keepdims=True)
    dims = min(ECAPA_DIMS, emb.shape[0] - 1, emb.shape[1])
    reduced = PCA(n_components=dims, random_state=0).fit_transform(emb)
    return np.hstack([_z(reduced), PROSODY_WEIGHT * _z(pros)])


def choose_k(X: np.ndarray, ks=range(4, 17), seed: int = 0) -> tuple[int, np.ndarray]:
    from sklearn.cluster import KMeans
    from sklearn.metrics import silhouette_score

    best = (-2.0, 0, None)
    for k in ks:
        labels = KMeans(n_clusters=k, n_init=10, random_state=seed).fit_predict(X)
        score = silhouette_score(X, labels, sample_size=min(2000, len(X)), random_state=seed)
        if score > best[0]:
            best = (score, k, labels)
    return best[1], best[2]


LABEL_SCHEMA = {
    "type": "object",
    "properties": {"clusters": {"type": "array", "items": {
        "type": "object",
        "properties": {"id": {"type": "string"}, "label": {"type": "string"},
                       "sex": {"enum": ["male", "female", "mixed"]}, "description": {"type": "string"}},
        "required": ["id", "label", "sex", "description"]}}},
    "required": ["clusters"],
}
LABEL_SYSTEM = """An audiobook narrator reads a novel alone, putting on different voices for narration, characters, moods and in-world announcements. His recorded lines were grouped by how they sound (voice timbre, pitch, pitch range, loudness, pace).
For each group you get sample transcript lines, earlier per-line guesses (kind/speaker/sex/mood) and a sound summary. Give each group:
- label: a short name for the voice, e.g. "young woman, warm", "gruff older man", "tense action narration", "system announcement", "calm narration"
- sex: of the voice being performed ("mixed" if the group is not one sex)
- description: one sentence on the delivery, saying which characters it is used for if clear"""


def label_clusters(summaries: list[dict], client: httpx.Client | None = None) -> dict[str, dict]:
    ids = [s["id"] for s in summaries]
    user = "\n\n".join(json.dumps(s, ensure_ascii=False) for s in summaries)
    labels: dict[str, dict] = {}
    for _attempt in range(2):
        try:
            reply = bonsai.chat_json(LABEL_SYSTEM, user, LABEL_SCHEMA, client)
        except ValueError:
            continue
        for e in reply.get("clusters", []):
            if e.get("id") in ids:
                labels[e["id"]] = {"label": e["label"], "sex": e.get("sex", "mixed"), "description": e.get("description", "")}
        if set(labels) == set(ids):
            break
    for i in ids:
        labels.setdefault(i, {"label": f"cluster {i}", "sex": "mixed", "description": ""})
    return labels


ASSIGN_SYSTEM = """You choose which recorded narrator voice should read each line of a novel aloud.
{context}

Available voices:
{menu}

For every numbered line marked TAG return the id of the voice that best fits how that line should be performed: match the speaker (sex, age, temperament) for dialogue, and the scene's tension for narration. Lines marked CONTEXT are only there to help you work out who is speaking."""


def assign_clusters(texts: list[str], menu: dict[str, str], context: str,
                    client: httpx.Client | None = None) -> list[str | None]:
    ids = sorted(menu)
    schema = {
        "type": "object",
        "properties": {"picks": {"type": "array", "items": {
            "type": "object",
            "properties": {"i": {"type": "integer"}, "cluster": {"enum": ids}},
            "required": ["i", "cluster"]}}},
        "required": ["picks"],
    }
    lines = "\n".join(f"- {i}: {menu[i]}" for i in ids)
    system = ASSIGN_SYSTEM.format(context=context, menu=lines)
    return bonsai.label_units(texts, system, schema, lambda e: e["cluster"], None, client)
