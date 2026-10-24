"""Chapter HTML to paragraphs, quote-level units, and TTS-sized chunks."""

import html
import re
from dataclasses import dataclass

_HEADER = re.compile(r"^\s*(Translator|Editor|Proofreader)\s*:", re.I)
_QUOTE_OPEN = "“\""
_QUOTE_CLOSE = {"“": "”", '"': '"'}

# Same order as ReadaloudTTS.TextChunker: sentence end > ;/: > comma > whitespace.
_SPLITS = [
    re.compile(r"[.!?][\"'”’)\]]*\s+"),
    re.compile(r"[;:]\s+"),
    re.compile(r",\s+"),
    re.compile(r"\s+"),
]


@dataclass
class Unit:
    idx: int
    para: int
    text: str
    quoted: bool


def html_to_paragraphs(doc: str) -> list[str]:
    text = re.sub(r"<\s*br\s*/?>|</\s*(p|div|h\d|li)\s*>", "\n", doc, flags=re.I)
    text = html.unescape(re.sub(r"<[^>]+>", "", text))
    lines = (line.strip() for line in text.split("\n"))
    return [line for line in lines if line and not _HEADER.match(line)]


def _split_para(para: str) -> list[tuple[str, bool]]:
    pieces: list[tuple[str, bool]] = []
    i = 0
    while i < len(para):
        start = min((p for p in (para.find(q, i) for q in _QUOTE_OPEN) if p >= 0), default=-1)
        if start < 0:
            pieces.append((para[i:], False))
            break
        if start > i:
            pieces.append((para[i:start], False))
        close = para.find(_QUOTE_CLOSE[para[start]], start + 1)
        end = len(para) if close < 0 else close + 1
        pieces.append((para[start:end], True))
        i = end
    return pieces


def split_units(paragraphs: list[str]) -> list[Unit]:
    units: list[Unit] = []
    for p, para in enumerate(paragraphs):
        for text, quoted in _split_para(para):
            units.append(Unit(len(units), p, text, quoted))
    return units


def _split_point(window: str) -> int | None:
    for pattern in _SPLITS:
        matches = list(pattern.finditer(window))
        if matches:
            return matches[-1].end()
    return None


def chunk(text: str, max_chars: int = 400) -> list[str]:
    remaining = text.strip()
    out: list[str] = []
    while remaining:
        if len(remaining) <= max_chars:
            out.append(remaining)
            break
        pos = _split_point(remaining[:max_chars]) or max_chars
        out.append(remaining[:pos].strip())
        remaining = remaining[pos:].strip()
    return out
