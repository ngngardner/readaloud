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


def egemma_encoder(device: str = "cuda:1"):
    """EmbeddingGemma 2 with only its audio encoder loaded. bfloat16 or float32 only: float16 returns NaNs."""
    import torch
    from sentence_transformers import SentenceTransformer

    dtype = torch.float32 if device == "cpu" else torch.bfloat16
    m = SentenceTransformer("google/embeddinggemma-2", device=device, config_kwargs={"vision_config": None},
                            model_kwargs={"torch_dtype": dtype})
    return lambda samples: m.encode({"audio": {"array": samples, "sampling_rate": ECAPA_RATE}})


def _z(a: np.ndarray) -> np.ndarray:
    sd = a.std(axis=0)
    return (a - a.mean(axis=0)) / np.where(sd > 0, sd, 1)


def feature_matrix(emb: np.ndarray, pros: np.ndarray) -> np.ndarray:
    from sklearn.decomposition import PCA

    emb = emb / np.linalg.norm(emb, axis=1, keepdims=True)
    dims = min(ECAPA_DIMS, emb.shape[0] - 1, emb.shape[1])
    reduced = PCA(n_components=dims, random_state=0).fit_transform(emb)
    return np.hstack([_z(reduced), PROSODY_WEIGHT * _z(pros)])


def _reduce(a: np.ndarray) -> np.ndarray:
    from sklearn.decomposition import PCA

    a = a / np.maximum(np.linalg.norm(a, axis=1, keepdims=True), 1e-9)
    return _z(PCA(n_components=min(ECAPA_DIMS, a.shape[0] - 1, a.shape[1]), random_state=0).fit_transform(a))


def voice_space(ecapa: np.ndarray, egemma: np.ndarray) -> np.ndarray:
    """ECAPA (who is speaking) + EmbeddingGemma 2 (narration vs dialogue, delivery), 16 PCA dims each."""
    return np.hstack([_reduce(ecapa), _reduce(egemma)])


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
LABEL_SYSTEM = """An audiobook narrator reads a novel alone, putting on different voices for narration, characters, moods and in-world announcements. His recorded lines were first split into narration, female dialogue and male dialogue, then each of those was grouped by how it sounds (voice timbre, pitch, pitch range, loudness, pace).
For each group you get its broad group, sample transcript lines, earlier per-line guesses (speaker/mood), how intense the audio sounds (0-1) and a sound summary. Give each group:
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


# Tag-guided grouping: bonsai's text tags set the broad group, the audio confirms it, and
# sub-clusters inside each group find the narrator's distinct voices.
AGREE = 0.6


def group_of(tag: dict) -> str | None:
    if tag["kind"] == "narration":
        return "narration"
    return tag["sex"] if tag["sex"] in ("female", "male") else None


def probe_scores(X: np.ndarray, tagged: list[dict]) -> dict[str, np.ndarray]:
    """Out-of-fold audio probabilities of dialogue, female (vs male) and intense delivery."""
    from sklearn.linear_model import LogisticRegression
    from sklearn.model_selection import cross_val_predict

    def oof(mask, y):
        if len(set(y[mask])) < 2:
            return np.full(len(X), float(y[mask].mean()) if mask.any() else 0.0)
        clf = LogisticRegression(max_iter=2000, class_weight="balanced")
        p = np.zeros(len(X))
        p[mask] = cross_val_predict(clf, X[mask], y[mask], cv=5, method="predict_proba")[:, 1]
        if (~mask).any():
            p[~mask] = clf.fit(X[mask], y[mask]).predict_proba(X[~mask])[:, 1]
        return p

    tags = [t["tag"] for t in tagged]
    everyone = np.ones(len(X), bool)
    dialogue = np.array([t["kind"] == "dialogue" for t in tags])
    sexed = dialogue & np.array([t["sex"] in ("female", "male") for t in tags])
    return {
        "dialogue": oof(everyone, dialogue),
        "female": oof(sexed, np.array([t["sex"] == "female" for t in tags])),
        "intense": oof(everyone, np.array([t["mood"] in ("intense", "action") for t in tags])),
    }


def confident(tagged: list[dict], scores: dict[str, np.ndarray]) -> np.ndarray:
    ok = np.zeros(len(tagged), bool)
    for i, t in enumerate(tagged):
        tag = t["tag"]
        if tag["kind"] == "narration":
            ok[i] = scores["dialogue"][i] <= 1 - AGREE
        elif tag["sex"] == "female":
            ok[i] = scores["dialogue"][i] >= AGREE and scores["female"][i] >= AGREE
        elif tag["sex"] == "male":
            ok[i] = scores["dialogue"][i] >= AGREE and scores["female"][i] <= 1 - AGREE
    return ok


def subclusters(X: np.ndarray, groups: list[str | None], mask: np.ndarray, min_size: int = 40,
                max_k: int = 4) -> list[str | None]:
    from sklearn.cluster import KMeans

    labels: list[str | None] = [None] * len(X)
    groups_arr = np.array([g or "" for g in groups])
    for g in sorted({g for g in groups if g}):
        idx = np.flatnonzero(mask & (groups_arr == g))
        if len(idx) == 0:
            continue
        k = int(np.clip(len(idx) // min_size, 1, max_k))
        raw = KMeans(k, n_init=10, random_state=0).fit_predict(X[idx]) if k > 1 else np.zeros(len(idx), int)
        order = [c for c, _ in sorted(enumerate(np.bincount(raw)), key=lambda kv: -kv[1])]
        for i, c in zip(idx, raw):
            labels[i] = f"{g}-{order.index(c)}"
    return labels


def enforce_group(tags: list[dict], picks: list[str | None], groups: dict[str, str],
                  sizes: dict[str, int]) -> list[str | None]:
    """A passage's voice must come from its own group: female lines never get a male voice."""
    out = []
    for tag, pick in zip(tags, picks):
        want = group_of(tag)
        if want is None or (pick is not None and groups.get(pick) == want):
            out.append(pick)
            continue
        same = [c for c, g in groups.items() if g == want]
        # No usable voice of the right group: None makes pick() use the narration clip, marked as a fallback.
        out.append(max(same, key=lambda c: sizes.get(c, 0)) if same else None)
    return out


def one_voice_per_speaker(tags: list[dict], picks: list[str | None]) -> list[str | None]:
    """Each character keeps the voice bonsai picked most often for them; narration stays per passage."""
    from collections import Counter

    votes: dict[str, Counter] = {}
    for tag, pick in zip(tags, picks):
        if tag["kind"] == "dialogue" and pick:
            votes.setdefault(tag["speaker"], Counter())[pick] += 1
    return [votes[t["speaker"]].most_common(1)[0][0] if t["kind"] == "dialogue" and t["speaker"] in votes else p
            for t, p in zip(tags, picks)]
