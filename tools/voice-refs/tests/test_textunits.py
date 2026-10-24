from voicerefs.textunits import chunk, html_to_paragraphs, split_units


def test_units_rejoin_exactly():
    paras = ["Hei Lou Lan said: “Father… you abandoned me—again.” She smiled."]
    units = split_units(paras)
    assert "".join(u.text for u in units) == paras[0]
    assert [u.quoted for u in units] == [False, True, False]


def test_units_carry_paragraph_and_index():
    units = split_units(["One.", "“Two,” he said."])
    assert [(u.idx, u.para) for u in units] == [(0, 0), (1, 1), (2, 1)]


def test_unclosed_quote_runs_to_paragraph_end():
    units = split_units(["“The quote continues into the next paragraph"])
    assert [u.quoted for u in units] == [True]


def test_chunk_respects_limit_and_sentences():
    text = ("Fang Yuan nodded. " * 40).strip()
    parts = chunk(text, 400)
    assert all(len(p) <= 400 for p in parts)
    assert all(p.endswith(".") for p in parts)
    assert " ".join(parts) == text


def test_chunk_short_text_is_one_chunk():
    assert chunk("  Hello there.  ", 400) == ["Hello there."]


def test_html_to_paragraphs_drops_header():
    html = "<p>Chapter 946</p><p>Translator: Atlas Studios</p><p>Hei Lou Lan&rsquo;s eyes</p>"
    assert html_to_paragraphs(html) == ["Chapter 946", "Hei Lou Lan’s eyes"]
