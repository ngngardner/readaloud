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


from voicerefs.clusters import confident, enforce_group, group_of, probe_scores, subclusters


def _tagged(kinds, sexes):
    return [{"tag": {"kind": k, "speaker": "x", "sex": s, "mood": "calm"}} for k, s in zip(kinds, sexes)]


def test_group_of():
    assert group_of({"kind": "narration", "sex": "unknown"}) == "narration"
    assert group_of({"kind": "dialogue", "sex": "female"}) == "female"
    assert group_of({"kind": "dialogue", "sex": "male"}) == "male"
    assert group_of({"kind": "dialogue", "sex": "unknown"}) is None


def test_probe_scores_learn_separable_audio():
    rng = np.random.default_rng(0)
    n = 300
    kinds = ["dialogue"] * 200 + ["narration"] * 100
    sexes = ["female"] * 100 + ["male"] * 100 + ["unknown"] * 100
    X = np.vstack([rng.normal([3, 3], 0.5, (100, 2)), rng.normal([3, -3], 0.5, (100, 2)),
                   rng.normal([-3, 0], 0.5, (100, 2))])
    s = probe_scores(X, _tagged(kinds, sexes))
    assert s["dialogue"][:200].mean() > 0.9 and s["dialogue"][200:].mean() < 0.1
    assert s["female"][:100].mean() > 0.9 and s["female"][100:200].mean() < 0.1
    assert len(s["intense"]) == n


def test_confident_requires_text_and_audio_agreement():
    tagged = _tagged(["dialogue", "dialogue", "narration", "dialogue"], ["female", "female", "unknown", "male"])
    scores = {"dialogue": np.array([0.9, 0.9, 0.2, 0.9]), "female": np.array([0.8, 0.3, 0.5, 0.1])}
    assert confident(tagged, scores).tolist() == [True, False, True, True]


def test_subclusters_split_within_group():
    rng = np.random.default_rng(2)
    X = np.vstack([rng.normal([0, 0], 0.3, (60, 2)), rng.normal([5, 5], 0.3, (60, 2)), rng.normal([9, 0], 0.3, (30, 2))])
    groups = ["male"] * 120 + ["female"] * 30
    mask = np.ones(150, bool)
    mask[0] = False
    labels = subclusters(X, groups, mask, min_size=40, max_k=4)
    assert labels[0] is None
    assert len({labels[i] for i in range(1, 60)}) == 1 and labels[1] != labels[60]
    assert {labels[i] for i in range(120, 150)} == {"female-0"}


def test_enforce_group_overrides_wrong_sex():
    groups = {"female-0": "female", "male-0": "male", "male-1": "male", "narration-0": "narration"}
    sizes = {"female-0": 50, "male-0": 200, "male-1": 300, "narration-0": 900}
    tags = [{"kind": "dialogue", "sex": "female"}, {"kind": "dialogue", "sex": "male"},
            {"kind": "narration", "sex": "unknown"}, {"kind": "dialogue", "sex": "unknown"}]
    picks = ["male-0", "male-0", "female-0", "male-1"]
    assert enforce_group(tags, picks, groups, sizes) == ["female-0", "male-0", "narration-0", "male-1"]


def test_one_voice_per_speaker():
    from voicerefs.clusters import one_voice_per_speaker

    tags = [{"kind": "dialogue", "speaker": "Fear Gu"}, {"kind": "dialogue", "speaker": "Fear Gu"},
            {"kind": "dialogue", "speaker": "Fear Gu"}, {"kind": "narration", "speaker": "narrator"},
            {"kind": "narration", "speaker": "narrator"}]
    picks = ["narration-3", "female-1", "narration-3", "narration-0", "narration-1"]
    assert one_voice_per_speaker(tags, picks) == ["narration-3", "narration-3", "narration-3", "narration-0", "narration-1"]


def test_enforce_group_without_usable_cluster_falls_back():
    groups = {"male-0": "male", "narration-0": "narration"}
    assert enforce_group([{"kind": "dialogue", "sex": "female"}], ["male-0"], groups, {"male-0": 10}) == [None]


def test_dialogue_never_gets_narration_voice():
    groups = {"male-0": "male", "male-2": "male", "female-0": "female", "narration-3": "narration"}
    sizes = {"male-0": 235, "male-2": 167, "female-0": 48, "narration-3": 119}
    tags = [{"kind": "dialogue", "sex": "unknown"}, {"kind": "dialogue", "sex": "male"}]
    assert enforce_group(tags, ["narration-3", "narration-3"], groups, sizes) == ["male-0", "male-0"]
