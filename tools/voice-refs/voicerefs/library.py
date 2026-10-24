"""Reference clip candidates, screening helpers, and the per-category library."""

import json
import re
from dataclasses import asdict, dataclass
from difflib import SequenceMatcher
from pathlib import Path

import numpy as np

from .bonsai import Tag
from .config import FALLBACK_REF

MIN_S, MAX_S = 6.0, 15.0
MAX_GAP_S = 1.0
SILENCE_DBFS = -45.0
FRAME_S = 0.02


@dataclass
class Candidate:
    category: str
    speaker: str
    start: float
    end: float
    text: str


@dataclass
class RefClip:
    category: str
    file: str
    transcript: str
    speaker: str
    start: float
    end: float
    score: float = 0.0
    fallback: bool = False


def category_of(tag: Tag) -> str | None:
    strong = tag.mood in ("intense", "action")
    if tag.kind == "narration":
        return "narration_action" if strong else "narration_calm"
    if tag.sex == "female":
        return "female_intense" if strong else "female_calm"
    if tag.sex == "male":
        return "male_intense" if strong else "male_casual"
    return None


def _category_key(seg: dict) -> tuple[str, str] | None:
    cat = category_of(Tag(**seg["tag"]))
    return None if cat is None else (cat, seg["tag"]["speaker"])


def candidates(tagged: list[dict], key=_category_key) -> list[Candidate]:
    """Merge contiguous segments sharing key(seg) = (category, speaker) into 6–15 s spans."""
    out: list[Candidate] = []
    run: list[dict] = []
    run_key = None

    def flush():
        if run and run[-1]["end"] - run[0]["start"] >= MIN_S:
            out.append(Candidate(run_key[0], run_key[1], run[0]["start"], run[-1]["end"],
                                 " ".join(s["text"] for s in run)))

    for seg in tagged:
        seg_key = key(seg)
        contiguous = run and seg["start"] - run[-1]["end"] < MAX_GAP_S
        fits = run and seg["end"] - run[0]["start"] <= MAX_S
        if seg_key is not None and seg_key == run_key and contiguous and fits:
            run.append(seg)
            continue
        flush()
        run, run_key = ([seg], seg_key) if seg_key is not None else ([], None)
    flush()
    return out


def _frame_db(samples: np.ndarray, rate: int) -> np.ndarray:
    n = max(1, int(rate * FRAME_S))
    frames = samples[: len(samples) // n * n].reshape(-1, n)
    rms = np.sqrt(np.mean(np.square(frames), axis=1))
    return 20 * np.log10(np.maximum(rms, 1e-9))


def signal_ok(samples: np.ndarray, rate: int) -> bool:
    db = _frame_db(samples, rate)
    voiced = np.flatnonzero(db > SILENCE_DBFS)
    if len(voiced) == 0:
        return False
    db = db[voiced[0]: voiced[-1] + 1]
    overall = 10 * np.log10(np.mean(10 ** (db / 10)))
    if not -35.0 <= overall <= -12.0:
        return False
    longest = run = 0
    for quiet in db <= SILENCE_DBFS:
        run = run + 1 if quiet else 0
        longest = max(longest, run)
    return longest * FRAME_S <= 1.2


_SPEECH = r"(said|says|asked|explained|replied|told|added|called|shouted|yelled|whispered|muttered|continued|answered|admitted|agreed|grumbled|laughed)"
_ATTRIBUTION = re.compile(
    rf"\b([A-Z][a-z]+|he|she|they)\s+{_SPEECH}\b"  # "Humphrey said"
    rf"|\b{_SPEECH}\s+[A-Z][a-z]+\b"  # "said Humphrey"
    r"|,\s+([A-Z][a-z]+|he|she|they)\s+[a-z]+ed\b"  # ", she scolded" / ", Belinda cautioned"
)


def has_attribution(text: str) -> bool:
    """A dialogue tag like "Farrah explained" means the clip also contains narration."""
    return bool(_ATTRIBUTION.search(text))


def whole_sentences(text: str) -> bool:
    """Starts at the start of a sentence and ends at the end of one."""
    t = text.strip().lstrip("“\"'")
    return bool(t) and t[0].isupper() and t.rstrip("”\"' ")[-1:] in (".", "!", "?")


def _ends_sentence(word: str) -> bool:
    return word.rstrip("”\"')")[-1:] in (".", "!", "?")


def trim_to_sentences(words: list[tuple[str, float, float]]) -> tuple[float, float, str] | None:
    """Drop words before the first sentence start and after the last sentence end."""
    first = next((i for i, (w, _, _) in enumerate(words)
                  if w.lstrip("“\"'")[:1].isupper() and (i == 0 or _ends_sentence(words[i - 1][0]))), None)
    if first is None:
        return None
    last = next((i for i in range(len(words) - 1, first - 1, -1) if _ends_sentence(words[i][0])), None)
    if last is None:
        return None
    kept = words[first:last + 1]
    return kept[0][1], kept[-1][2], " ".join(w for w, _, _ in kept)


def _words(text: str) -> list[str]:
    return [w for w in re.sub(r"[^\w\s]", "", text.lower()).split() if w]


def word_agreement(expected: str, heard: str) -> float:
    a, b = _words(expected), _words(heard)
    if not a:
        return 0.0
    matched = sum(block.size for block in SequenceMatcher(None, a, b).get_matching_blocks())
    return matched / len(a)


def select(clips: list[RefClip], per_category: int = 3) -> dict[str, list[RefClip]]:
    lib: dict[str, list[RefClip]] = {}
    by_cat: dict[str, list[RefClip]] = {}
    for c in clips:
        by_cat.setdefault(c.category, []).append(c)
    for cat, group in by_cat.items():
        group = sorted(group, key=lambda c: -c.score)
        chosen, speakers = [], set()
        for c in group:
            if c.speaker not in speakers and len(chosen) < per_category:
                chosen.append(c)
                speakers.add(c.speaker)
        for c in group:
            if c not in chosen and len(chosen) < per_category:
                chosen.append(c)
        lib[cat] = sorted(chosen, key=lambda c: -c.score)
    return lib


def pick(lib: dict[str, list[RefClip]], category: str | None) -> RefClip:
    clips = lib.get(category or "", [])
    if clips:
        return clips[0]
    return RefClip(category or "none", FALLBACK_REF[0], FALLBACK_REF[1], "narrator", 0.0, 0.0, fallback=True)


def save_library(lib: dict[str, list[RefClip]], path: Path) -> None:
    path.write_text(json.dumps({cat: [asdict(c) for c in clips] for cat, clips in lib.items()}, indent=1))


def load_library(path: Path) -> dict[str, list[RefClip]]:
    return {cat: [RefClip(**c) for c in clips] for cat, clips in json.loads(path.read_text()).items()}
