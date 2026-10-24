"""Exploration: score audio embeddings and clustering methods against bonsai's text tags.

The tags are noisy (they come from transcript text, and a Whisper segment can mix narration and
speech), so these scores compare methods against each other rather than measuring truth.

  uv run python explore/evaluate.py
"""

import json
from collections import Counter

import numpy as np
from sklearn.cluster import AgglomerativeClustering, KMeans
from sklearn.decomposition import PCA
from sklearn.metrics import balanced_accuracy_score, normalized_mutual_info_score
from sklearn.mixture import GaussianMixture
from sklearn.model_selection import cross_val_predict
from sklearn.neighbors import KNeighborsClassifier

from voicerefs.config import WORK_DIR

SRC = WORK_DIR / "source"
PCA_DIMS = 16


def z(a):
    sd = a.std(axis=0)
    return (a - a.mean(axis=0)) / np.where(sd > 0, sd, 1)


def reduce(a, dims=PCA_DIMS):
    a = a / np.maximum(np.linalg.norm(a, axis=1, keepdims=True), 1e-9)
    return z(PCA(n_components=min(dims, a.shape[1]), random_state=0).fit_transform(a))


def load_embeddings():
    feats = np.load(SRC / "features.npz")
    pros = z(feats["pros"])
    embs = {"prosody": pros, "ecapa": reduce(feats["emb"])}
    for name in ("wavlm", "emotion", "egemma"):
        path = SRC / f"emb-{name}.npy"
        if path.exists():
            raw = np.load(path)
            if name == "emotion":
                embs["emotion-adv"] = z(raw[:, :3])  # arousal, dominance, valence
                raw = raw[:, 3:]
            embs[name] = reduce(raw)
    for name in list(embs):
        if name not in ("prosody", "emotion-adv"):
            embs[f"{name}+prosody"] = np.hstack([embs[name], 2 * pros])
    if "emotion-adv" in embs and "ecapa" in embs:
        embs["ecapa+adv+prosody"] = np.hstack([embs["ecapa"], 2 * embs["emotion-adv"], 2 * pros])
    return embs


def targets(tagged):
    kind = np.array([t["tag"]["kind"] for t in tagged])
    sex = np.array([t["tag"]["sex"] for t in tagged])
    mood = np.array([t["tag"]["mood"] for t in tagged])
    speaker = np.array([t["tag"]["speaker"] for t in tagged])
    dial = kind == "dialogue"
    top = [s for s, _ in Counter(speaker[dial]).most_common(6)]
    return {
        "kind": (np.ones(len(kind), bool), kind),
        "sex(dialogue)": (dial & np.isin(sex, ["male", "female"]), sex),
        "intense": (np.ones(len(kind), bool), np.isin(mood, ["intense", "action"])),
        "speaker(top6)": (dial & np.isin(speaker, top), speaker),
    }, np.char.add(np.char.add(kind, "/"), np.where(dial, sex, "-"))


def probe(X, tgts):
    out = {}
    for name, (mask, y) in tgts.items():
        knn = KNeighborsClassifier(n_neighbors=15, weights="distance")
        pred = cross_val_predict(knn, X[mask], y[mask], cv=5)
        out[name] = balanced_accuracy_score(y[mask], pred)
    return out


def female_capture(labels, sexkind):
    """Share of female dialogue that lands in clusters where female dialogue is at least 40%."""
    fem = sexkind == "dialogue/female"
    caught = 0
    for c in set(labels):
        in_c = labels == c
        if fem[in_c].mean() >= 0.4:
            caught += (fem & in_c).sum()
    return caught / max(1, fem.sum())


def cluster_scores(X, combined):
    rows = []
    for k in (6, 8, 10, 12):
        for method, fit in (
            ("kmeans", lambda: KMeans(k, n_init=10, random_state=0).fit_predict(X)),
            ("gmm", lambda: GaussianMixture(k, covariance_type="diag", random_state=0).fit(X).predict(X)),
            ("ward", lambda: AgglomerativeClustering(k, linkage="ward").fit_predict(X)),
        ):
            labels = fit()
            rows.append((method, k, normalized_mutual_info_score(combined, labels), female_capture(labels, combined)))
    return rows


def main():
    tagged = json.loads((SRC / "tagged.json").read_text())
    tgts, combined = targets(tagged)
    print("label counts:", dict(Counter(combined)))
    embs = load_embeddings()
    report = {}
    print(f"\n{'embedding':22s} " + " ".join(f"{t:>14s}" for t in tgts))
    for name, X in embs.items():
        scores = probe(X, tgts)
        report[name] = {"probe": scores}
        print(f"{name:22s} " + " ".join(f"{scores[t]:14.3f}" for t in tgts))
    print(f"\n{'embedding':22s} {'best clustering (by NMI)':28s} {'NMI':>6s} {'female caught':>14s}")
    for name, X in embs.items():
        rows = cluster_scores(X, combined)
        report[name]["clusters"] = rows
        best = max(rows, key=lambda r: r[2])
        best_f = max(rows, key=lambda r: r[3])
        print(f"{name:22s} {best[0] + ' k=' + str(best[1]):28s} {best[2]:6.3f} {best[3]:14.2f}"
              f"   (best female capture: {best_f[0]} k={best_f[1]} {best_f[3]:.2f})")
    (WORK_DIR / "explore-report.json").write_text(json.dumps(report, indent=1, default=float))


if __name__ == "__main__":
    main()
