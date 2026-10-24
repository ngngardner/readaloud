import json

import httpx
import numpy as np

from voicerefs.clusters import assign_clusters, choose_k, feature_matrix, label_clusters, prosody
from voicerefs.library import candidates


def test_choose_k_finds_separated_blobs():
    rng = np.random.default_rng(0)
    centers = np.array([[0, 0], [10, 0], [0, 10]])
    X = np.vstack([c + rng.normal(0, 0.5, (40, 2)) for c in centers])
    k, labels = choose_k(X, ks=range(2, 7))
    assert k == 3
    assert len(set(labels[:40])) == 1 and len(set(labels)) == 3


def test_feature_matrix_shape_and_scale():
    rng = np.random.default_rng(1)
    emb = rng.normal(size=(50, 192))
    pros = rng.normal(size=(50, 4)) * 100
    X = feature_matrix(emb, pros)
    assert X.shape == (50, 16 + 4)
    assert np.allclose(X[:, :16].std(axis=0), 1, atol=1e-6)
    assert np.allclose(X[:, 16:].std(axis=0), 2, atol=1e-6)  # prosody weighted x2


def test_prosody_tracks_pitch():
    rate = 16000
    t = np.arange(rate * 2) / rate
    low = prosody(0.3 * np.sin(2 * np.pi * 110 * t), rate)
    high = prosody(0.3 * np.sin(2 * np.pi * 220 * t), rate)
    assert abs((high[0] - low[0]) - 12) < 0.5  # an octave is 12 semitones


def _seg(start, end, cluster, speaker="Farrah"):
    return {"start": start, "end": end, "text": str(start), "cluster": cluster,
            "tag": {"kind": "dialogue", "speaker": speaker, "sex": "female", "mood": "calm"}}


def test_candidates_by_cluster_key():
    segs = [_seg(0, 4, 2), _seg(4, 8, 2), _seg(8, 12, 5), _seg(12, 16, 5), _seg(16, 20, 5)]
    key = lambda s: (f"c{s['cluster']}", s["tag"]["speaker"])
    cands = candidates(segs, key=key)
    assert [(c.category, c.start, c.end) for c in cands] == [("c2", 0, 8), ("c5", 8, 20)]


def _client(contents):
    calls = []

    def handler(request):
        calls.append(json.loads(request.content))
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": contents.pop(0)}}]})

    return httpx.Client(transport=httpx.MockTransport(handler)), calls


def test_label_clusters_fills_missing():
    client, _ = _client([json.dumps({"clusters": [{"id": "c0", "label": "young woman, warm", "sex": "female"}]})] * 2)
    labels = label_clusters([{"id": "c0", "lines": ["hi"]}, {"id": "c1", "lines": ["yo"]}], client=client)
    assert labels["c0"]["label"] == "young woman, warm"
    assert labels["c1"]["label"] == "cluster c1"


def test_assign_clusters_menu_and_missing():
    reply = json.dumps({"picks": [{"i": 0, "cluster": "c1"}, {"i": 1, "cluster": "c0"}]})
    client, calls = _client([reply])
    menu = {"c0": "calm narration", "c1": "young woman, warm"}
    picks = assign_clusters(["“Mother!”", "The fog was thick."], menu, "ctx", client=client)
    assert picks == ["c1", "c0"]
    schema = calls[0]["response_format"]["json_schema"]["schema"]
    assert schema["properties"]["picks"]["items"]["properties"]["cluster"]["enum"] == ["c0", "c1"]
    assert "young woman, warm" in calls[0]["messages"][0]["content"]
