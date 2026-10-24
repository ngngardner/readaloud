from voicerefs.bonsai import Tag
from voicerefs.chapter import MAX_NARRATION, build_passages
from voicerefs.textunits import split_units

NARR = Tag("narration", "narrator", "unknown", "calm")
HLL = Tag("dialogue", "Hei Lou Lan", "female", "intense")


def test_attribution_separates_quotes():
    para = "Then “Father!” she said. “You left me.”"
    units = split_units([para])
    assert [u.text for u in units] == ["Then ", "“Father!”", " she said. ", "“You left me.”"]
    passages = build_passages(units, [NARR, HLL, NARR, HLL])
    assert [p.category for p in passages] == ["narration_calm", "female_intense", "narration_calm", "female_intense"]
    assert "".join(p.text for p in passages) == para
    assert [p.idx for p in passages] == [0, 1, 2, 3]


def test_calm_narration_paragraphs_merge():
    units = split_units(["The fog was thick.", "The pines were silent."])
    passages = build_passages(units, [NARR, NARR])
    assert len(passages) == 1
    assert passages[0].text == "The fog was thick.\nThe pines were silent."


def test_dialogue_in_new_paragraph_is_new_passage():
    units = split_units(["“Mother!”", "“Mother, is father alright?”"])
    passages = build_passages(units, [HLL, HLL])
    assert len(passages) == 2


def test_long_narration_splits_at_limit():
    para = "x" * (MAX_NARRATION - 10)
    units = split_units([para, para])
    passages = build_passages(units, [NARR, NARR])
    assert len(passages) == 2
