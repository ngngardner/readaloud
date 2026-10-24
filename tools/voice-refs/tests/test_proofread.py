from voicerefs.names import respell_variants, score_heard
from voicerefs.proofread import misheard


def test_variants_change_one_syllable_at_a_time():
    v = respell_variants("Feng Jiu Ge")
    assert v[0] == "Fung Jyo Guh"
    assert "Fung Jyo Gur" in v
    assert all(len(x.split()) == 3 for x in v)
    assert len(v) == len(set(v))


def test_variants_for_er():
    assert {"Hwahng Ar", "Hwahng Er"} <= set(respell_variants("Huang Er"))


def test_score_prefers_spelling_read_as_written():
    assert score_heard("Fung Jyo Gur nodded slowly.", "Fung Jyo Gur", "Feng Jiu Ge") > \
        score_heard("Fung Jyo Goo nodded slowly.", "Fung Jyo Guh", "Feng Jiu Ge")
    assert score_heard("Feng Jiu Ge nodded slowly.", "Fung Jyo Guh", "Feng Jiu Ge") == 1.0


def test_misheard_finds_substituted_words():
    expected = "However, the feathermen wanted freedom, they did not want to be restricted."
    heard = "However, the fearmen wanted freedom. They did not want to be restricted."
    assert misheard(expected, heard) == [("feathermen", "fearmen")]


def test_misheard_ignores_listed_words():
    assert misheard("Hay Chung smiled.", "Hey Chung smiled.", ignore={"hay", "chung"}) == []


def test_combine_best_takes_best_option_per_syllable():
    from voicerefs.names import combine_best

    scores = {"Fung Jyo Guh": 0.5, "Fung Jyo Gur": 0.9, "Fung Jyoh Guh": 0.4, "Fuhng Jyo Guh": 0.7}
    assert combine_best("Feng Jiu Ge", scores) == "Fuhng Jyo Gur"
    assert combine_best("Feng Jiu Ge", {}) == "Fung Jyo Guh"


def test_misheard_treats_possessive_like_the_name():
    assert misheard("Run Dzoo’s heart.", "Runzu's heart.", ignore={"run", "dzoo"}) == []
