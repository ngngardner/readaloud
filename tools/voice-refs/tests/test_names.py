from voicerefs.names import apply_names


def test_names_longest_first_and_possessive():
    m = {"Hei Lou Lan": "Hay Low Lahn", "Hei Cheng": "Hay Chung", "Fang": "Fahng", "Fang Yuan": "Fahng Yooen"}
    out = apply_names("Hei Lou Lan's father Hei Cheng met Fang Yuan.", m)
    assert out == "Hay Low Lahn's father Hay Chung met Fahng Yooen."


def test_names_word_boundary():
    assert apply_names("Fangs bared.", {"Fang": "Fahng"}) == "Fangs bared."


def test_names_empty_mapping_is_identity():
    assert apply_names("Fang Yuan.", {}) == "Fang Yuan."
