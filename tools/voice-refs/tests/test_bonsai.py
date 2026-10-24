import json

import httpx

from voicerefs.bonsai import FALLBACK_TAG, Tag, tag_units


def _reply(content: str) -> httpx.Response:
    return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": content}}]})


def _tags(indices):
    return json.dumps({"tags": [
        {"i": i, "kind": "dialogue", "speaker": f"S{i}", "sex": "female", "mood": "calm"} for i in indices
    ]})


def _client(replies):
    calls = []

    def handler(request):
        calls.append(json.loads(request.content))
        return _reply(replies.pop(0))

    return httpx.Client(transport=httpx.MockTransport(handler), base_url="http://bonsai"), calls


def test_valid_response_gives_tags_in_order():
    client, calls = _client([_tags([0, 1, 2])])
    tags = tag_units(["a", "b", "c"], "ctx", client=client)
    assert tags == [Tag("dialogue", f"S{i}", "female", "calm") for i in range(3)]
    body = calls[0]
    assert body["response_format"]["type"] == "json_schema"
    assert body["chat_template_kwargs"] == {"enable_thinking": False}
    assert body["temperature"] == 0.3


def test_invalid_json_is_retried_once():
    client, calls = _client(["not json", _tags([0, 1])])
    tags = tag_units(["a", "b"], "ctx", client=client)
    assert len(calls) == 2
    assert tags[1].speaker == "S1"


def test_missing_index_after_retry_gets_fallback():
    client, calls = _client([_tags([0, 1, 3]), _tags([0, 1, 3])])
    tags = tag_units(["a", "b", "c", "d"], "ctx", client=client)
    assert len(calls) == 2
    assert tags[2] == FALLBACK_TAG
    assert tags[3].speaker == "S3"


def test_duplicate_index_triggers_retry():
    client, calls = _client([_tags([0, 0, 1]), _tags([0, 1])])
    tag_units(["a", "b"], "ctx", client=client)
    assert len(calls) == 2


def test_windows_cover_all_units_once():
    n = 95
    replies = [_tags(range(0, 40)), _tags(range(40, 80)), _tags(range(80, 95))]
    client, calls = _client(replies)
    tags = tag_units([f"u{i}" for i in range(n)], "ctx", client=client)
    assert len(calls) == 3
    assert [t.speaker for t in tags] == [f"S{i}" for i in range(n)]
    # second window shows the 5 previous units as context
    assert "u35" in calls[1]["messages"][1]["content"]


def test_pure_speech_check():
    from voicerefs.bonsai import pure_speech

    client, calls = _client([json.dumps({"pure_speech": False, "reason": "contains 'Vincent turned'"})])
    assert pure_speech("Vincent turned to look at Humphrey. Mr. Geller, you failed.", client=client) is False
    client, _ = _client([json.dumps({"pure_speech": True, "reason": ""})])
    assert pure_speech("The protection I set up in here will hide your aura.", client=client) is True
    client, _ = _client(["garbage", "garbage"])
    assert pure_speech("x", client=client) is False
