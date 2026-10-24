"""voicerefs: one subcommand per pipeline stage. Every stage reads/writes under WORK_DIR."""

import argparse
import json
import subprocess
from dataclasses import asdict
from pathlib import Path

from . import audio, bonsai, chapter, laya_check, library, names, textunits, tts, whisper
from .config import CATEGORIES, SOURCE_BOOK, VOICES_DIR, WORK_DIR

PIECE_S = 600


def cmd_source(args) -> None:
    out_dir = WORK_DIR / "source"
    pieces_dir = out_dir / "pieces"
    pieces_dir.mkdir(parents=True, exist_ok=True)
    all_segments = []
    for stretch in args.stretches.split(","):
        start, dur = (float(x) for x in stretch.split(":"))
        t = start
        while t < start + dur:
            piece_dur = min(PIECE_S, start + dur - t)
            cache = pieces_dir / f"{int(t):06d}.json"
            if cache.exists():
                segs = [whisper.Segment(**s) for s in json.loads(cache.read_text())]
            else:
                wav = audio.extract(SOURCE_BOOK, t, piece_dur, pieces_dir / f"{int(t):06d}.wav")
                segs = whisper.transcribe(wav, offset_s=t)
                cache.write_text(json.dumps([asdict(s) for s in segs]))
                wav.unlink()
            print(f"{int(t)}s: {len(segs)} segments", flush=True)
            all_segments.extend(segs)
            t += piece_dur
    (out_dir / "segments.json").write_text(json.dumps([asdict(s) for s in all_segments]))
    print(f"wrote {len(all_segments)} segments")


SOURCE_CONTEXT = (
    "The lines are a Whisper transcript of the audiobook He Who Fights with Monsters, read by one male "
    "narrator who does character voices. Quotation marks are missing, so decide from the wording and "
    "attributions whether a line is spoken dialogue. A line may mix narration and speech; tag it by what "
    "most of it is. Main characters include Jason (male), Farrah (female), Rufus (male), Gary (male), "
    "Clive (male), Humphrey (male), Sophie (female), Belinda (female), Danielle (female), Neil (male)."
)


def cmd_tag_source(args) -> None:
    src = WORK_DIR / "source"
    segments = json.loads((src / "segments.json").read_text())
    tags = bonsai.tag_units([s["text"] for s in segments], SOURCE_CONTEXT)
    for seg, tag in zip(segments, tags):
        seg["tag"] = asdict(tag)
    (src / "tagged.json").write_text(json.dumps(segments))
    counts: dict[tuple, int] = {}
    for t in tags:
        key = (t.kind, t.sex, t.mood)
        counts[key] = counts.get(key, 0) + 1
    for key, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(n, *key)


PAD_S = 0.12
MAX_TRIES = 30
AGREEMENT_MIN = 0.85
ACTION_MIN = 0.7


def cmd_library(args) -> None:
    tagged = json.loads((WORK_DIR / "source" / "tagged.json").read_text())
    cands = library.candidates(tagged)
    # Bonsai rarely calls narration "action"; laya decides that for narration candidates.
    for c in cands:
        if c.category.startswith("narration"):
            c.category = "narration_action" if laya_check.ask(laya_check.ACTION, c.text) >= ACTION_MIN else "narration_calm"
    cut_dir = WORK_DIR / "library" / "cuts"
    accepted: list[library.RefClip] = []
    for cat in CATEGORIES:
        pool = sorted((c for c in cands if c.category == cat), key=lambda c: abs((c.end - c.start) - 10))
        print(f"{cat}: {len(pool)} candidates", flush=True)
        ok = 0
        for n, c in enumerate(pool[:MAX_TRIES]):
            wav = audio.extract(SOURCE_BOOK, c.start - PAD_S, c.end - c.start + 2 * PAD_S, cut_dir / f"{cat}-{n}.wav")
            samples, rate = audio.read(wav)
            if not library.signal_ok(samples, rate):
                continue
            heard = " ".join(s.text for s in whisper.transcribe(wav))
            score = library.word_agreement(c.text, heard)
            if score < AGREEMENT_MIN:
                continue
            accepted.append(library.RefClip(cat, str(wav), heard, c.speaker, c.start, c.end, score=score))
            ok += 1
            if ok >= args.per_category * 2:
                break
    lib = library.select(accepted, per_category=args.per_category)
    VOICES_DIR.mkdir(parents=True, exist_ok=True)
    for cat, clips in lib.items():
        for n, clip in enumerate(clips):
            name = f"hwfwm-{cat}-{n}.wav"
            samples, rate = audio.read(Path(clip.file))
            audio.write(VOICES_DIR / name, samples, rate)
            (VOICES_DIR / name).with_suffix(".txt").write_text(clip.transcript)
            clip.file = name
    library.save_library(lib, WORK_DIR / "library.json")
    for cat in CATEGORIES:
        clips = lib.get(cat, [])
        if not clips:
            print(f"{cat}: NO CLIP (matched methods fall back to heath-miller.wav)")
        for clip in clips:
            print(f"{cat}: {clip.speaker} {clip.end - clip.start:.1f}s {clip.score:.2f} {clip.transcript[:80]}")


CHAPTER_CONTEXT = (
    "The lines are from Reverend Insanity, a Chinese web novel in English translation. Characters are "
    "referred to by Chinese names (e.g. Fang Yuan is male, Hei Lou Lan is female, Hei Cheng is male, "
    "Blazing Heaven Demoness is female)."
)
NAMES_FILE = Path(__file__).resolve().parent.parent / "names" / "reverend-insanity.json"
BOOK_ID = 12


def _chapter_dir(number: int) -> Path:
    return WORK_DIR / f"ch{number:04d}"


def cmd_chapter(args) -> None:
    out = _chapter_dir(args.number)
    out.mkdir(parents=True, exist_ok=True)
    src = f"/var/lib/readaloud/data/files/books/{BOOK_ID}/chapters/{args.number:04d}.html"
    html = subprocess.run(["ssh", "root@pylon", "cat", src], check=True, capture_output=True, text=True).stdout
    (out / "chapter.html").write_text(html)
    paragraphs = textunits.html_to_paragraphs(html)
    units = textunits.split_units(paragraphs)
    tags = bonsai.tag_units([u.text for u in units], CHAPTER_CONTEXT)
    for i, (u, t) in enumerate(zip(units, tags)):
        if t.kind == "narration" and laya_check.ask(laya_check.ACTION, u.text) >= ACTION_MIN:
            tags[i] = bonsai.Tag(t.kind, t.speaker, t.sex, "action")
    passages = chapter.build_passages(units, tags)
    (out / "passages.json").write_text(json.dumps(
        {"title": paragraphs[0], "passages": [asdict(p) for p in passages]}, ensure_ascii=False, indent=1))
    for p in passages:
        print(f"{p.idx:3d} {p.category or '-':16s} {p.tag.speaker[:18]:18s} {p.text[:70]!r}")


NAMES_SCHEMA = {
    "type": "object",
    "properties": {"names": {"type": "array", "items": {
        "type": "object",
        "properties": {"name": {"type": "string"}, "hanzi": {"type": "string"}},
        "required": ["name", "hanzi"]}}},
    "required": ["names"],
}
NAMES_SYSTEM = """You prepare a pronunciation list for a narrator reading a Chinese web novel in English translation.
List every Chinese name written in pinyin in the text: people, nicknames, clans, tribes and places, exactly as written (e.g. "Hei Lou Lan", "Fang Yuan", "Huang Er", "Hei" from "Hei tribe"). Skip anything translated into English, such as "Blazing Heaven Demoness", "Verdant Great Sun" or "Spirit Affinity House".
For each, give the Chinese characters (simplified) the name is written with in the original novel."""


def cmd_names(args) -> None:
    from pypinyin import Style, pinyin

    text = "\n".join(textunits.html_to_paragraphs((_chapter_dir(args.number) / "chapter.html").read_text()))
    reply = bonsai.chat_json(NAMES_SYSTEM, text, NAMES_SCHEMA)
    existing = json.loads(NAMES_FILE.read_text()) if NAMES_FILE.exists() else {}
    for entry in reply["names"]:
        name = entry["name"].strip()
        spelled = names.respell(name)
        if not name or name in existing or name not in text or spelled is None:
            continue
        hanzi = entry["hanzi"].strip() if names.hanzi_matches(name, entry["hanzi"].strip()) else ""
        tones = " ".join(r[0] for r in pinyin(hanzi, style=Style.TONE)) if hanzi else " ".join(names.syllables(name))
        existing[name] = {"hanzi": hanzi, "pinyin": tones, "respelling": spelled}
    NAMES_FILE.parent.mkdir(parents=True, exist_ok=True)
    NAMES_FILE.write_text(json.dumps(dict(sorted(existing.items())), ensure_ascii=False, indent=1) + "\n")
    for name, e in existing.items():
        print(f"{name:16s} {e['hanzi'] or '-':6s} {e['pinyin']:18s} {e['respelling']}")


def _load_passages(number: int) -> list[chapter.Passage]:
    raw = json.loads((_chapter_dir(number) / "passages.json").read_text())["passages"]
    return [chapter.Passage(p["idx"], p["text"], bonsai.Tag(**p["tag"]), p["category"]) for p in raw]


def cmd_generate(args) -> None:
    ch = _chapter_dir(args.number)
    lib_path = WORK_DIR / "library.json"
    lib = library.load_library(lib_path) if lib_path.exists() else {}
    entries = json.loads(NAMES_FILE.read_text())
    name_map = {name: e["respelling"] for name, e in entries.items()}
    methods = args.methods.split(",") if args.methods else tts.METHODS
    if any(m != "current" for m in methods) and not lib:
        raise SystemExit("library.json missing: run `voicerefs library` before generating matched methods")
    gen_path = ch / "generation.json"
    gen = json.loads(gen_path.read_text()) if gen_path.exists() else {"passages": {}, "names": {}}
    result = tts.generate(_load_passages(args.number), lib, name_map, ch / "audio", methods=methods)
    for idx, by_method in result.items():
        gen["passages"].setdefault(idx, {}).update(by_method)
    gen["names"] = tts.generate_names(entries, ch / "audio")
    gen_path.write_text(json.dumps(gen, ensure_ascii=False, indent=1))
    failed = [(i, m) for i, bm in gen["passages"].items() for m, r in bm.items() if "failed" in r]
    print(f"generated {len(gen['passages'])} passages; {len(failed)} failed: {failed}")


def main() -> None:
    parser = argparse.ArgumentParser(prog="voicerefs")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("source", help="transcribe stretches of the source audiobook")
    p.add_argument("--stretches", required=True, help="start:duration seconds, comma separated")
    p.set_defaults(func=cmd_source)
    p = sub.add_parser("tag-source", help="tag source segments with bonsai")
    p.set_defaults(func=cmd_tag_source)
    p = sub.add_parser("library", help="screen candidates and write the reference clip library")
    p.add_argument("--per-category", type=int, default=3)
    p.set_defaults(func=cmd_library)
    for name, func, help_ in (("chapter", cmd_chapter, "tag a chapter and build passages"),
                              ("names", cmd_names, "extract the chapter's names into the book's name list")):
        p = sub.add_parser(name, help=help_)
        p.add_argument("--number", type=int, default=195, help="readaloud chapter number (195 = Chapter 944)")
        p.set_defaults(func=func)
    p = sub.add_parser("generate", help="generate passage audio for each method, plus name samples")
    p.add_argument("--number", type=int, default=195)
    p.add_argument("--methods", default="", help="comma separated subset of current,matched,matched_names")
    p.set_defaults(func=cmd_generate)
    args = parser.parse_args()
    args.func(args)
