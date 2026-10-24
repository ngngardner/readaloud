import json

import httpx

from voicerefs import plan, readaloud
from voicerefs.bonsai import Tag
from voicerefs.chapter import Passage
from voicerefs.library import RefClip

NARR = RefClip("Narration", "hwfwm-narration-0.wav", "The walls were black.", "narrator", 0, 9)
FEMALE = RefClip("Female", "hwfwm-female-0.wav", "Get out of my sight.", "Farrah", 0, 7)
LIB = {"narration-0": [NARR], "female-0": [FEMALE]}
NARRATION = Tag("narration", "narrator", "unknown", "calm")
HER = Tag("dialogue", "Hei Lou Lan", "female", "intense")


def _p(idx, text, tag, cluster):
    return Passage(idx, text, tag, None, cluster)


def test_chunks_carry_book_text_spoken_text_and_clip():
    chunks = plan.chunks_for([_p(0, "Feng Jiu Ge smiled.", NARRATION, "narration-0")], LIB,
                             {"Feng Jiu Ge": "Fung Jyo Guhh"})
    assert chunks == [{"text": "Feng Jiu Ge smiled.", "spoken": "Fung Jyo Guhh smiled.",
                       "voice": "/models/voices/hwfwm-narration-0.wav", "reference_text": "The walls were black."}]


def test_neighbouring_passages_with_the_same_clip_share_a_request():
    passages = [_p(0, "He walked in.", NARRATION, "narration-0"),
                _p(1, "The hall was cold.", NARRATION, "narration-0"),
                _p(2, "“Leave.”", HER, "female-0"),
                _p(3, "She turned away.", NARRATION, "narration-0")]
    chunks = plan.chunks_for(passages, LIB, {})
    assert [c["text"] for c in chunks] == ["He walked in.\nThe hall was cold.", "“Leave.”", "She turned away."]
    assert [c["voice"].rsplit("/", 1)[1] for c in chunks] == [
        "hwfwm-narration-0.wav", "hwfwm-female-0.wav", "hwfwm-narration-0.wav"]


def test_long_passages_are_cut_at_the_chunk_limit():
    text = ("Fang Yuan nodded slowly. " * 40).strip()
    chunks = plan.chunks_for([_p(0, text, NARRATION, "narration-0")], LIB, {})
    assert len(chunks) > 1
    assert all(len(c["spoken"]) <= 400 for c in chunks)
    assert " ".join(c["text"] for c in chunks) == text


def test_merging_stops_at_the_chunk_limit():
    a, b = "A" * 250 + ".", "B" * 250 + "."
    chunks = plan.chunks_for([_p(0, a, NARRATION, "narration-0"), _p(1, b, NARRATION, "narration-0")], LIB, {})
    assert [c["text"] for c in chunks] == [a, b]


def test_document_names_the_voice_and_temperature():
    doc = plan.document([_p(0, "Hi.", NARRATION, "narration-0")], LIB, {}, temperature=0.6)
    assert doc["model"] == "breeze-tts-2" and doc["voice"] == "heath-miller"
    assert doc["temperature"] == 0.6 and len(doc["chunks"]) == 1


def test_remembered_speakers_keep_their_voice_across_chapters():
    tags = [{"kind": "dialogue", "speaker": "Fang Yuan", "sex": "male"},
            {"kind": "dialogue", "speaker": "Bai Ning Bing", "sex": "male"},
            {"kind": "narration", "speaker": "narrator", "sex": "unknown"}]
    groups = {"male-0": "male", "male-1": "male", "narration-0": "narration"}
    memory = {"Fang Yuan": "male-1"}
    picks = plan.remember_speakers(tags, ["male-0", "male-0", "narration-0"], memory, groups)
    assert picks == ["male-1", "male-0", "narration-0"]
    assert memory == {"Fang Yuan": "male-1", "Bai Ning Bing": "male-0"}


def test_a_remembered_voice_of_the_wrong_group_is_not_reused():
    tags = [{"kind": "dialogue", "speaker": "Gu", "sex": "female"}]
    memory = {"Gu": "male-0"}
    picks = plan.remember_speakers(tags, ["female-0"], memory, {"male-0": "male", "female-0": "female"})
    assert picks == ["female-0"]
    assert memory == {"Gu": "female-0"}


def test_new_names_are_respelled_and_english_words_skipped():
    text = "Gu Yue Bo met Long. A long road lay ahead. Fang Yuan watched."
    found = ["Gu Yue Bo", "Long", "Fang Yuan", "Spirit Spring", "Xyzzy"]
    new = plan.new_names(found, text, existing={"Fang Yuan": "Fahng Yoo-en"})
    assert set(new) == {"Gu Yue Bo"}
    assert new["Gu Yue Bo"] == "Goo Yweh Baw"


def _api(routes):
    calls = []

    def handler(request):
        calls.append((request.method, request.url.path, json.loads(request.content) if request.content else None))
        return httpx.Response(200, json=routes[(request.method, request.url.path)])

    return httpx.Client(transport=httpx.MockTransport(handler), base_url="http://readaloud"), calls


def test_readaloud_client_lists_fetches_and_uploads():
    client, calls = _api({
        ("GET", "/api/books/12/chapters"): {"chapters": [{"id": 5, "number": 210, "title": "C", "voice_plan": False}]},
        ("GET", "/api/books/12/chapters/5/text"): {"id": 5, "number": 210, "title": "C", "html": "<p>x</p>"},
        ("PUT", "/api/books/12/chapters/5/voice-plan"): {"chunks": 1, "queue": "queued"},
    })
    api = readaloud.Readaloud(client)
    assert api.chapters(12)[0]["number"] == 210
    assert api.text(12, 5)["html"] == "<p>x</p>"
    assert api.put_plan(12, 5, {"chunks": []}) == {"chunks": 1, "queue": "queued"}
    assert calls[-1] == ("PUT", "/api/books/12/chapters/5/voice-plan", {"chunks": []})


def test_wordless_passages_join_a_neighbour_instead_of_going_alone():
    # Breeze can fail on a request with no words in it ("***", a silent "……").
    passages = [_p(0, "“Leave.”", HER, "female-0"),
                _p(1, "***", NARRATION, "narration-0"),
                _p(2, "“Now.”", HER, "female-0")]
    chunks = plan.chunks_for(passages, LIB, {})
    assert [c["text"] for c in chunks] == ["“Leave.”\n***", "“Now.”"]


def test_a_wordless_first_passage_joins_the_next():
    passages = [_p(0, "……", NARRATION, "narration-0"), _p(1, "“Leave.”", HER, "female-0")]
    assert [c["text"] for c in plan.chunks_for(passages, LIB, {})] == ["……\n“Leave.”"]


def test_single_word_names_are_not_learned():
    # Learned names apply to the whole book; "Men" or "Long" would rewrite ordinary words in later chapters.
    text = "Men Ke bowed to Long."
    assert plan.new_names(["Men Ke", "Long"], text, existing={}) == {"Men Ke": "Mun Kuh"}
