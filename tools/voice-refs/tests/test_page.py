import json
import re

import numpy as np

from voicerefs import audio
from voicerefs.page import build


def _setup(tmp_path):
    ch = tmp_path / "ch"
    (ch / "audio").mkdir(parents=True)
    voices = tmp_path / "voices"
    voices.mkdir()
    audio.write(voices / "heath-miller.wav", np.zeros(2400))
    audio.write(voices / "hwfwm-female_calm-0.wav", np.zeros(2400))
    for f in ["000-current.opus", "000-matched.opus", "000-matched_names.opus",
              "001-matched.opus", "001-matched_names.opus", "name-00-original.opus"]:
        (ch / "audio" / f).write_bytes(b"x")
    tag = {"kind": "dialogue", "speaker": "Feng Jin Huang", "sex": "female", "mood": "calm"}
    narr = {"kind": "narration", "speaker": "narrator", "sex": "unknown", "mood": "calm"}
    (ch / "passages.json").write_text(json.dumps({"title": "Chapter 944: Test", "passages": [
        {"idx": 0, "text": "“Mother!”", "tag": tag, "category": "female_calm"},
        {"idx": 1, "text": "Fang Yuan nodded.", "tag": narr, "category": "narration_calm"},
    ]}))
    hm = {"category": "current", "file": "heath-miller.wav", "transcript": "t", "speaker": "narrator",
          "start": 0, "end": 0, "score": 0, "fallback": False}
    fc = dict(hm, category="female_calm", file="hwfwm-female_calm-0.wav", speaker="Farrah", start=10, end=19)
    fb = dict(hm, category="narration_calm", fallback=True)
    (ch / "generation.json").write_text(json.dumps({
        "passages": {
            "0": {"current": {"text": "“Mother!”", "ref": hm, "file": "000-current.opus"},
                  "matched": {"text": "“Mother!”", "ref": fc, "file": "000-matched.opus"},
                  "matched_names": {"text": "“Mother!”", "ref": fc, "file": "000-matched_names.opus"}},
            "1": {"current": {"text": "Fang Yuan nodded.", "ref": hm, "failed": "HTTP 500"},
                  "matched": {"text": "Fang Yuan nodded.", "ref": fb, "file": "001-matched.opus"},
                  "matched_names": {"text": "Fahng Yoo-en nodded.", "ref": fb, "file": "001-matched_names.opus"}},
        },
        "names": {"Fang Yuan": {"original": "name-00-original.opus"}},
    }))
    names = tmp_path / "names.json"
    names.write_text(json.dumps({"Fang Yuan": {"hanzi": "方源", "pinyin": "fāng yuán", "respelling": "Fahng Yoo-en"}}))
    return ch, voices, names


def _data(html: str) -> dict:
    m = re.search(r'<script type="application/json" id="data">(.*?)</script>', html, re.S)
    return json.loads(m.group(1))


def test_build_embeds_data_and_copies_audio(tmp_path):
    ch, voices, names = _setup(tmp_path)
    out = tmp_path / "site"
    index = build(ch, names, voices, out)
    html = index.read_text()
    assert "<title>" in html[:8192]
    data = _data(html)
    assert data["title"] == "Chapter 944: Test"
    texts = [p["text"] for p in data["passages"]]
    assert texts == ["“Mother!”", "Fang Yuan nodded."]
    p1 = data["passages"][1]["methods"]
    assert p1["current"]["failed"] == "HTTP 500" and "file" not in p1["current"]
    assert p1["matched"]["ref"]["fallback"] is True
    assert data["names"][0]["name"] == "Fang Yuan" and data["names"][0]["audio"]["original"]
    refs = {m["ref"]["audio"] for p in data["passages"] for m in p["methods"].values()}
    assert len(refs) == 2
    paths = re.findall(r'"(audio/[^"]+)"', html)
    assert paths and all((out / p).exists() for p in paths)


def test_build_escapes_script_close(tmp_path):
    ch, voices, names = _setup(tmp_path)
    pj = json.loads((ch / "passages.json").read_text())
    pj["passages"][0]["text"] = "</script><b>x"
    (ch / "passages.json").write_text(json.dumps(pj))
    html = build(ch, names, voices, tmp_path / "site").read_text()
    assert _data(html)["passages"][0]["text"] == "</script><b>x"


def test_build_lists_discovered_voices(tmp_path):
    ch, voices, names = _setup(tmp_path)
    cl = tmp_path / "clusters.json"
    cl.write_text(json.dumps({
        "labels": {"female-0": {"label": "female, warm", "sex": "female", "description": "Farrah's voice."},
                   "male-1": {"label": "male, steady", "sex": "male", "description": "Jason."}},
        "groups": {"female-0": "female", "male-1": "male"}, "sizes": {"female-0": 48, "male-1": 169}}))
    lib = tmp_path / "library.json"
    lib.write_text(json.dumps({"female-0": [{"category": "female, warm", "file": "hwfwm-female_calm-0.wav",
                                             "transcript": "There are villages.", "speaker": "Farrah",
                                             "start": 1, "end": 8, "score": 1, "fallback": False}],
                               "male-1": []}))
    html = build(ch, names, voices, tmp_path / "site", clusters_path=cl, library_path=lib).read_text()
    v = _data(html)["voices"]
    assert [x["id"] for x in v] == ["female-0", "male-1"]
    assert v[0]["clips"][0]["audio"].startswith("audio/ref-")
    assert v[1]["clips"] == []


def test_build_includes_word_fixes(tmp_path):
    ch, voices, names = _setup(tmp_path)
    words = tmp_path / "words.json"
    words.write_text(json.dumps({"feathermen": "feather men"}))
    html = build(ch, names, voices, tmp_path / "site", words_path=words).read_text()
    assert _data(html)["fixes"] == {"feathermen": "feather men"}
