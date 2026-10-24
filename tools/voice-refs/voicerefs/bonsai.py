"""Client for bonsai-text (Ternary-Bonsai served by llama-server) and unit tagging."""

import json
from dataclasses import dataclass

import httpx

from .config import BONSAI_URL

WINDOW = 40
CONTEXT = 5

KINDS = ["narration", "dialogue"]
SEXES = ["male", "female", "unknown"]
MOODS = ["calm", "casual", "intense", "action"]


@dataclass(frozen=True)
class Tag:
    kind: str
    speaker: str
    sex: str
    mood: str


FALLBACK_TAG = Tag("narration", "narrator", "unknown", "calm")

TAG_SCHEMA = {
    "type": "object",
    "properties": {
        "tags": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "i": {"type": "integer"},
                    "kind": {"enum": KINDS},
                    "speaker": {"type": "string"},
                    "sex": {"enum": SEXES},
                    "mood": {"enum": MOODS},
                },
                "required": ["i", "kind", "speaker", "sex", "mood"],
            },
        }
    },
    "required": ["tags"],
}

SYSTEM = """You label lines of a novel for an audiobook narrator.
{context}

For every numbered line marked TAG, return one entry with:
- i: the line number
- kind: "dialogue" if the line is a character speaking aloud (a quotation), otherwise "narration"
- speaker: for dialogue, the character's name (or a short description like "the mother" if unnamed); for narration, "narrator"
- sex: the speaker's sex for dialogue ("male" / "female", "unknown" only if truly impossible to tell); for narration, "unknown"
- mood: the delivery the line calls for: "calm", "casual", "intense" (angry, afraid, shouting, desperate), or "action" (fast physical action or combat)

Use the surrounding lines to work out who is speaking: attributions like "she said" may come before or after the quote, and speakers usually alternate in a conversation. Lines marked CONTEXT are only there to help; do not return entries for them."""


def chat_json(system: str, user: str, schema: dict, client: httpx.Client | None = None, max_tokens: int = 4096) -> dict:
    """Raises httpx.HTTPError on transport failure, ValueError on unusable output."""
    client = client or httpx.Client(timeout=900)
    resp = client.post(
        BONSAI_URL,
        json={
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
            "temperature": 0.3,
            "max_tokens": max_tokens,
            "chat_template_kwargs": {"enable_thinking": False},
            "response_format": {"type": "json_schema", "json_schema": {"name": "reply", "schema": schema}},
        },
    )
    resp.raise_for_status()
    try:
        choice = resp.json()["choices"][0]
        content = choice["message"]["content"]
    except (KeyError, IndexError, TypeError) as exc:
        raise ValueError(f"unexpected reply shape: {exc}") from exc
    if choice.get("finish_reason") == "length":
        raise ValueError("reply truncated at max_tokens")
    try:
        return json.loads(content)
    except json.JSONDecodeError as exc:
        raise ValueError(f"reply is not JSON: {exc}") from exc


def _window(texts, start, end, system, schema, parse, client) -> dict[int, object]:
    lines = [f"[{i}] CONTEXT: {texts[i]}" for i in range(max(0, start - CONTEXT), start)]
    lines += [f"[{i}] TAG: {texts[i]}" for i in range(start, end)]
    if end < len(texts):
        lines += [f"[{i}] CONTEXT: {texts[i]}" for i in range(end, min(len(texts), end + CONTEXT))]
    want = set(range(start, end))
    key = next(iter(schema["properties"]))
    best: dict[int, object] = {}
    for _attempt in range(2):
        try:
            reply = chat_json(system, "\n".join(lines), schema, client)
        except ValueError:
            continue
        got: dict[int, object] = {}
        seen: list[int] = []
        for e in reply.get(key, []):
            i = e.get("i")
            seen.append(i)
            if i in want:
                got[i] = parse(e)
        if sorted(seen) == sorted(want):
            return got
        if len(got) > len(best):
            best = got
    return best


def label_units(texts: list[str], system: str, schema: dict, parse, fallback, client: httpx.Client | None = None) -> list:
    """Label every text in windows of WINDOW, retrying a window once when indices are missing or duplicated."""
    client = client or httpx.Client(timeout=900)
    out: list = []
    for start in range(0, len(texts), WINDOW):
        end = min(start + WINDOW, len(texts))
        got = _window(texts, start, end, system, schema, parse, client)
        out.extend(got.get(i, fallback) for i in range(start, end))
    return out


def tag_units(texts: list[str], context: str, client: httpx.Client | None = None) -> list[Tag]:
    return label_units(texts, SYSTEM.format(context=context), TAG_SCHEMA,
                       lambda e: Tag(e["kind"], e["speaker"], e["sex"], e["mood"]), FALLBACK_TAG, client)


PURE_SCHEMA = {
    "type": "object",
    "properties": {"pure_speech": {"type": "boolean"}, "reason": {"type": "string"}},
    "required": ["pure_speech", "reason"],
}
PURE_SYSTEM = """This is a transcript of a short audiobook clip. Answer pure_speech = true only if the whole clip is one character speaking aloud: no narration (e.g. "Vincent turned to look at him"), no dialogue tags (e.g. "Humphrey interjected", "she asked"), and no second character replying. Give a short reason."""


def pure_speech(text: str, client: httpx.Client | None = None) -> bool:
    for _attempt in range(2):
        try:
            return bool(chat_json(PURE_SYSTEM, text, PURE_SCHEMA, client, max_tokens=200)["pure_speech"])
        except (ValueError, KeyError):
            continue
    return False
