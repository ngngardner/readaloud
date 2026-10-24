import numpy as np

from voicerefs.bonsai import Tag
from voicerefs.library import (
    RefClip, candidates, category_of, pick, select, signal_ok, word_agreement,
)


def test_category_table():
    assert category_of(Tag("dialogue", "Farrah", "female", "calm")) == "female_calm"
    assert category_of(Tag("dialogue", "Farrah", "female", "casual")) == "female_calm"
    assert category_of(Tag("dialogue", "Farrah", "female", "intense")) == "female_intense"
    assert category_of(Tag("dialogue", "Farrah", "female", "action")) == "female_intense"
    assert category_of(Tag("dialogue", "Jason", "male", "casual")) == "male_casual"
    assert category_of(Tag("dialogue", "Jason", "male", "calm")) == "male_casual"
    assert category_of(Tag("dialogue", "Jason", "male", "intense")) == "male_intense"
    assert category_of(Tag("narration", "narrator", "unknown", "action")) == "narration_action"
    assert category_of(Tag("narration", "narrator", "unknown", "intense")) == "narration_action"
    assert category_of(Tag("narration", "narrator", "unknown", "calm")) == "narration_calm"
    assert category_of(Tag("dialogue", "someone", "unknown", "calm")) is None


def _seg(start, end, text, kind="dialogue", speaker="Farrah", sex="female", mood="calm"):
    return {"start": start, "end": end, "text": text,
            "tag": {"kind": kind, "speaker": speaker, "sex": sex, "mood": mood}}


def test_candidates_merge_same_speaker_and_split_at_change():
    segs = [_seg(0, 4, "a"), _seg(4, 8, "b"), _seg(8, 12, "c"),
            _seg(12, 16, "d", kind="narration", speaker="narrator", sex="unknown")]
    cands = candidates(segs)
    assert len(cands) == 1
    c = cands[0]
    assert (c.category, c.speaker, c.start, c.end, c.text) == ("female_calm", "Farrah", 0, 12, "a b c")


def test_candidates_cap_at_15s():
    segs = [_seg(i * 4, i * 4 + 4, str(i)) for i in range(6)]  # 24 s run
    cands = candidates(segs)
    assert all(6 <= c.end - c.start <= 15 for c in cands)
    assert [c.text for c in cands] == ["0 1 2", "3 4 5"]


def test_candidates_break_on_gap():
    segs = [_seg(0, 4, "a"), _seg(4, 8, "b"), _seg(20, 24, "c"), _seg(24, 28, "d")]
    assert [c.text for c in candidates(segs)] == ["a b", "c d"]


def test_signal_ok_rejects_internal_silence():
    rate = 24000
    tone = 0.1 * np.sin(2 * np.pi * 200 * np.arange(rate * 3) / rate)
    assert signal_ok(np.concatenate([tone, tone]), rate)
    assert not signal_ok(np.concatenate([tone, np.zeros(rate * 2), tone]), rate)


def test_signal_ok_rejects_too_quiet():
    rate = 24000
    tone = 0.001 * np.sin(2 * np.pi * 200 * np.arange(rate * 6) / rate)
    assert not signal_ok(tone, rate)


def test_word_agreement():
    assert word_agreement("I am afraid of my shadow", "I'm afraid of my shadow.") >= 0.6
    assert word_agreement("one two three four", "one two three four") == 1.0
    assert word_agreement("one two three four", "five six") == 0.0


def _clip(cat, speaker, score):
    return RefClip(cat, f"{cat}-{speaker}.wav", "t", speaker, 0, 8, score=score)


def test_select_ranks_and_prefers_distinct_speakers():
    clips = [_clip("female_calm", "Farrah", 0.9), _clip("female_calm", "Farrah", 0.95),
             _clip("female_calm", "Sophie", 0.8), _clip("male_casual", "Jason", 0.7)]
    lib = select(clips, per_category=2)
    assert [c.speaker for c in lib["female_calm"]] == ["Farrah", "Sophie"]
    assert lib["female_calm"][0].score == 0.95
    assert len(lib["male_casual"]) == 1


def test_pick_falls_back_when_category_empty():
    lib = {"female_calm": [], "male_casual": [_clip("male_casual", "Jason", 0.7)]}
    ref = pick(lib, "female_calm")
    assert ref.fallback and ref.file == "heath-miller.wav"
    assert pick(lib, None).fallback
    assert pick(lib, "male_casual").speaker == "Jason"


from voicerefs.library import has_attribution


def test_has_attribution():
    assert has_attribution("point for all the green marble, Farah explained. There")
    assert has_attribution("They don't, Humphrey said.")
    assert has_attribution("she asked quietly")
    assert not has_attribution("I never said I would go.")
    assert not has_attribution("The protection I set up in here will hide your aura.")


def test_whole_sentences():
    from voicerefs.library import whole_sentences

    assert whole_sentences("The protection I set up will hide your aura. But you can't stay here.")
    assert not whole_sentences("about gravity? No, you can't.")
    assert not whole_sentences("I never said the Mercer sent me. And I suppose I can")
    assert whole_sentences("Mother, is father alright?")


def test_trim_to_sentences():
    from voicerefs.library import trim_to_sentences

    words = [("gravity?", 0.0, 0.5), ("No,", 0.6, 0.9), ("you", 1.0, 1.2), ("can't.", 1.2, 1.6),
             ("Some", 1.8, 2.0), ("things", 2.0, 2.4), ("people", 2.4, 2.8)]
    assert trim_to_sentences(words) == (0.6, 1.6, "No, you can't.")
    assert trim_to_sentences([("and", 0, 1), ("then", 1, 2)]) is None
    whole = [("It", 0, 1), ("works.", 1, 2)]
    assert trim_to_sentences(whole) == (0, 2, "It works.")


def test_has_attribution_catches_any_ed_tag():
    assert has_attribution("I don't know what a flirty Santa Claus is, she scolded, but no.")
    assert has_attribution("Let's not go making assumptions, Belinda cautioned.")
    assert not has_attribution("It was finished, and nobody cared.")
