import json
from pathlib import Path

import numpy as np

from voicerefs.audio import level, rms_dbfs
from voicerefs.whisper import parse_verbose

FIXTURE = json.loads((Path(__file__).parent / "fixtures" / "verbose.json").read_text())


def test_parse_verbose_offsets_times():
    segs = parse_verbose(FIXTURE, offset_s=600)
    assert len(segs) == 2
    assert abs(segs[0].start - 600.7) < 1e-6
    assert abs(segs[0].end - 606.4) < 1e-6
    assert segs[0].text == "Jason watched in horror as its body started climbing up and around the outside of the well"
    word, ws, we = segs[0].words[0]
    assert word == "Jason" and abs(ws - 600.7) < 1e-6 and abs(we - 601.34) < 1e-6


def test_parse_verbose_null_confidences_become_none():
    segs = parse_verbose(FIXTURE)
    assert segs[0].avg_logprob is None and segs[0].no_speech_prob is None


def test_parse_verbose_keeps_confidences_when_present():
    js = json.loads(json.dumps(FIXTURE))
    js["segments"][0]["avg_logprob"] = -0.25
    js["segments"][0]["no_speech_prob"] = 0.01
    seg = parse_verbose(js)[0]
    assert seg.avg_logprob == -0.25 and seg.no_speech_prob == 0.01


def test_level_brings_sine_to_target():
    t = np.arange(24000) / 24000
    amp = 10 ** (-30 / 20) * np.sqrt(2)
    x = amp * np.sin(2 * np.pi * 220 * t)
    assert abs(rms_dbfs(x) + 30) < 0.1
    assert abs(rms_dbfs(level(x, -20.0)) + 20) < 0.1


def test_level_clips_to_unit_range():
    x = np.full(100, 0.5)
    assert np.max(np.abs(level(x, 0.0))) <= 1.0
