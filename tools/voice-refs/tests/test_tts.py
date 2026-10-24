import io
import json

import httpx
import numpy as np
import pytest
import soundfile as sf

from voicerefs.bonsai import Tag
from voicerefs.chapter import Passage
from voicerefs.library import RefClip
from voicerefs.tts import METHODS, TTSFailed, generate, speak


def _wav(seconds=0.5, rate=24000):
    buf = io.BytesIO()
    sf.write(buf, 0.1 * np.sin(np.arange(int(rate * seconds)) / 10), rate, format="WAV", subtype="PCM_16")
    return buf.getvalue()


def _client(statuses):
    calls = []

    def handler(request):
        calls.append(json.loads(request.content))
        status = statuses.pop(0)
        return httpx.Response(status, content=_wav() if status == 200 else b"err")

    return httpx.Client(transport=httpx.MockTransport(handler)), calls


def test_speak_retries_then_succeeds():
    client, calls = _client([503, 503, 200])
    out = speak("Hello.", "hwfwm-female_calm-0.wav", "ref text", client=client, backoff_s=0)
    assert len(calls) == 3 and len(out) == 12000


def test_speak_gives_up_after_three_failures():
    client, _ = _client([503, 503, 503])
    with pytest.raises(TTSFailed):
        speak("Hello.", "x.wav", "ref", client=client, backoff_s=0)


def test_speak_request_contract():
    client, calls = _client([200])
    speak("Hello.", "hwfwm-female_calm-0.wav", "ref text", client=client, backoff_s=0)
    body = calls[0]
    assert "speed" not in body and "speed" not in body["params"]
    assert body["model"] == "breeze-tts-2"
    assert body["voice"] == "/models/voices/hwfwm-female_calm-0.wav"
    assert body["params"] == {"reference_text": "ref text", "seed": "42", "text_chunk_size": "2000"}


def test_generate_records_failure_and_continues(tmp_path):
    passages = [
        Passage(0, "“Mother!”", Tag("dialogue", "Feng Jin Huang", "female", "intense"), "female_intense"),
        Passage(1, "Fang Yuan nodded.", Tag("narration", "narrator", "unknown", "calm"), "narration_calm"),
    ]
    lib = {"narration_calm": [RefClip("narration_calm", "hwfwm-narration_calm-0.wav", "t", "narrator", 0, 8)]}
    seen = []

    def synth(text, ref_file, ref_text):
        seen.append((text, ref_file))
        if text == "“Mother!”":
            raise TTSFailed("boom")
        return np.zeros(2400)

    result = generate(passages, lib, {"Fang Yuan": "Fahng Yoo-en"}, tmp_path, synth=synth)
    assert set(result["0"]) == set(METHODS)
    assert result["0"]["current"]["failed"] == "boom"
    assert result["0"]["matched"]["ref"]["fallback"] is True
    assert (tmp_path / result["1"]["matched"]["file"]).exists()
    assert ("Fahng Yoo-en nodded.", "hwfwm-narration_calm-0.wav") in seen
    assert ("Fang Yuan nodded.", "heath-miller.wav") in seen


def test_generate_skips_existing_outputs(tmp_path):
    p = [Passage(0, "Hi.", Tag("narration", "narrator", "unknown", "calm"), "narration_calm")]
    calls = []

    def synth(text, ref_file, ref_text):
        calls.append(text)
        return np.zeros(2400)

    generate(p, {}, {}, tmp_path, synth=synth)
    first = len(calls)
    generate(p, {}, {}, tmp_path, synth=synth)
    assert first == 3 and len(calls) == 3


def test_generate_names_forms(tmp_path):
    from voicerefs.tts import generate_names

    entries = {"Fang Yuan": {"hanzi": "方源", "respelling": "Fahng Yoo-en"},
               "Kong Jue": {"hanzi": "", "respelling": "Kong Jweh"}}
    seen = []

    def synth(text, ref_file, ref_text):
        seen.append(text)
        return np.zeros(2400)

    out = generate_names(entries, tmp_path, synth=synth)
    assert seen == ["Fang Yuan nodded slowly.", "Fahng Yoo-en nodded slowly.", "方源 nodded slowly.",
                    "Kong Jue nodded slowly.", "Kong Jweh nodded slowly."]
    assert set(out["Kong Jue"]) == {"original", "respelling"}
    assert all((tmp_path / f).exists() for forms in out.values() for f in forms.values())


def test_generate_limits_methods(tmp_path):
    p = [Passage(0, "Hi.", Tag("narration", "narrator", "unknown", "calm"), "narration_calm")]
    calls = []

    def synth(text, ref_file, ref_text):
        calls.append(ref_file)
        return np.zeros(2400)

    result = generate(p, {}, {}, tmp_path, synth=synth, methods=["current"])
    assert calls == ["heath-miller.wav"]
    assert list(result["0"]) == ["current"]


def test_plan_prefers_passage_cluster():
    from voicerefs.tts import _plan

    lib = {"c2": [RefClip("young woman, warm", "hwfwm-c2-0.wav", "t", "Farrah", 0, 8)]}
    p = Passage(0, "“Mother!”", Tag("dialogue", "Feng Jin Huang", "female", "calm"), "female_calm", cluster="c2")
    plan = _plan(p, lib, {})
    assert plan["matched"][1].file == "hwfwm-c2-0.wav"
    assert plan["current"][1].file == "heath-miller.wav"
