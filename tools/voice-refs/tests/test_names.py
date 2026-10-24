from voicerefs.names import apply_names


def test_names_longest_first_and_possessive():
    m = {"Hei Lou Lan": "Hay Low Lahn", "Hei Cheng": "Hay Chung", "Fang": "Fahng", "Fang Yuan": "Fahng Yooen"}
    out = apply_names("Hei Lou Lan's father Hei Cheng met Fang Yuan.", m)
    assert out == "Hay Low Lahn's father Hay Chung met Fahng Yooen."


def test_names_word_boundary():
    assert apply_names("Fangs bared.", {"Fang": "Fahng"}) == "Fangs bared."


def test_names_empty_mapping_is_identity():
    assert apply_names("Fang Yuan.", {}) == "Fang Yuan."


from voicerefs.names import hanzi_matches, respell, syllables


def test_syllables_parse_pinyin_words():
    assert syllables("Fang Yuan") == ["fang", "yuan"]
    assert syllables("Xiaoming") == ["xiao", "ming"]
    assert syllables("Verdant Great Sun") is None
    assert syllables("Hei Lou Lan") == ["hei", "lou", "lan"]


def test_respell_core_names():
    assert respell("Fang Yuan") == "Fahng Yoo-en"
    assert respell("Hei Lou Lan") == "Hay Loh Lahn"
    assert respell("Hei Cheng") == "Hay Chung"
    assert respell("Feng Jin Huang") == "Fung Jeen Hwahng"
    assert respell("Bai Qing") == "Bye Ching"
    assert respell("Kong Jue") == "Kong Jweh"
    assert respell("Xie") == "Shyeh"
    assert respell("Ren Zu") == "Run Dzoo"


def test_respell_apical_vowels_and_umlaut():
    assert respell("Shi") == "Shr"
    assert respell("Zi") == "Dzuh"
    assert respell("Xu") == "Shyoo"
    assert respell("Lü") == "Lyoo"


def test_respell_rejects_non_pinyin():
    assert respell("Blazing Heaven Demoness") is None


def test_hanzi_matches_checks_syllables():
    assert hanzi_matches("Fang Yuan", "方源")
    assert hanzi_matches("Hei Lou Lan", "黑楼兰")
    assert not hanzi_matches("Fang Yuan", "方")
    assert not hanzi_matches("Bai Qing", "白凝冰")
