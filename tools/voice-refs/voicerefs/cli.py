"""voicerefs: one subcommand per pipeline stage. Every stage reads/writes under WORK_DIR."""

import argparse
import json
import subprocess
from dataclasses import asdict
from pathlib import Path

from . import audio, bonsai, chapter, clusters, laya_check, library, names, page, textunits, tts, whisper
from .config import SOURCE_BOOK, VOICES_DIR, WORK_DIR

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
MAX_TRIES = 40
MIN_CLIP_S = 4.5
AGREEMENT_MIN = 0.85
ACTION_MIN = 0.7
SAMPLE_LINES = 15


def _summaries(tagged, labels, dist, pros, intense) -> list[dict]:
    import numpy as np
    from collections import Counter

    out = []
    lab = np.array([x or "" for x in labels])
    for cid in sorted({x for x in labels if x}):
        idx = np.flatnonzero(lab == cid)
        near = idx[np.argsort(dist[idx])][:SAMPLE_LINES]
        p = pros[idx].mean(axis=0)
        out.append({
            "id": cid, "group": cid.rsplit("-", 1)[0], "segments": int(len(idx)),
            "audio_intensity": round(float(intense[idx].mean()), 2),
            "sound": {"pitch_semitones_re_100hz": round(float(p[0]), 1), "pitch_range_st": round(float(p[1]), 1),
                      "loudness_dbfs": round(float(p[2]), 1), "words_per_second": round(float(p[4]), 2)},
            "moods": dict(Counter(tagged[i]["tag"]["mood"] for i in idx).most_common(4)),
            "speakers": dict(Counter(tagged[i]["tag"]["speaker"] for i in idx).most_common(5)),
            "lines": [tagged[i]["text"] for i in near],
        })
    return out


def cmd_cluster(args) -> None:
    import numpy as np
    from collections import Counter

    src = WORK_DIR / "source"
    tagged = json.loads((src / "tagged.json").read_text())
    feats = np.load(src / "features.npz")
    X = clusters.voice_space(feats["emb"], np.load(src / "emb-egemma.npy"))
    scores = clusters.probe_scores(X, tagged)
    ok = clusters.confident(tagged, scores)
    groups = [clusters.group_of(t["tag"]) for t in tagged]
    print("confident segments per group:", dict(Counter(g for g, o in zip(groups, ok) if o and g)),
          "of", dict(Counter(g for g in groups if g)))
    labels = clusters.subclusters(X, groups, ok, min_size=args.min_size, max_k=args.max_k)
    lab = np.array([x or "" for x in labels])
    dist = np.full(len(X), 99.0)
    for cid in set(labels) - {None}:
        idx = lab == cid
        dist[idx] = np.linalg.norm(X[idx] - X[idx].mean(axis=0), axis=1)
    summaries = _summaries(tagged, labels, dist, feats["pros"], scores["intense"])
    names_by_id = clusters.label_clusters(summaries)
    for sm in summaries:
        lab_ = names_by_id[sm["id"]]
        print(f"{sm['id']:>12} {sm['segments']:5d}  {lab_['label']}  |  {lab_['description']}")

    for seg, cid, d in zip(tagged, labels, dist):
        seg["cluster"], seg["centrality"] = cid, float(d)
    cands = library.candidates(tagged, key=lambda s: (s["cluster"], s["tag"]["speaker"]) if s["cluster"] else None)
    for c in cands:
        ds = [s["centrality"] for s in tagged if c.start <= s["start"] < c.end]
        c.centrality = float(np.mean(ds)) if ds else 99.0
    cut_dir = WORK_DIR / "library" / "cuts"
    lib: dict[str, list[library.RefClip]] = {}
    VOICES_DIR.mkdir(parents=True, exist_ok=True)
    for sm in summaries:
        cid, lab_ = sm["id"], names_by_id[sm["id"]]
        pool = sorted((c for c in cands if c.category == cid), key=lambda c: c.centrality)
        clips = []
        for n, c in enumerate(pool[:MAX_TRIES]):
            words = [tuple(w) for s in tagged if c.start <= s["start"] < c.end for w in s["words"]]
            trimmed = library.trim_to_sentences(words)
            if trimmed is None or trimmed[1] - trimmed[0] < MIN_CLIP_S:
                continue
            c.start, c.end, c.text = trimmed
            wav = audio.extract(SOURCE_BOOK, c.start - PAD_S, c.end - c.start + 2 * PAD_S, cut_dir / f"{cid}-{n}.wav")
            samples, rate = audio.read(wav)
            if not library.signal_ok(samples, rate):
                continue
            heard = " ".join(s.text for s in whisper.transcribe(wav))
            score = library.word_agreement(c.text, heard)
            if score < AGREEMENT_MIN or not library.whole_sentences(heard):
                continue
            if not cid.startswith("narration") and (library.has_attribution(heard) or not bonsai.pure_speech(heard)):
                continue
            name = f"hwfwm-{cid}-{len(clips)}.wav"
            audio.write(VOICES_DIR / name, samples, rate)
            (VOICES_DIR / name).with_suffix(".txt").write_text(heard)
            clips.append(library.RefClip(lab_["label"], name, heard, c.speaker, c.start, c.end, score=score))
            if len(clips) >= args.per_cluster:
                break
        lib[cid] = clips
        print(f"{cid}: {len(pool)} candidates, {len(clips)} clips" + (f" e.g. {clips[0].transcript[:70]!r}" if clips else ""))
    library.save_library(lib, WORK_DIR / "library.json")
    (WORK_DIR / "clusters.json").write_text(json.dumps(
        {"labels": names_by_id, "groups": {sm["id"]: sm["group"] for sm in summaries},
         "sizes": {sm["id"]: sm["segments"] for sm in summaries}, "summaries": summaries},
        ensure_ascii=False, indent=1))
    (src / "clustered.json").write_text(json.dumps(tagged))


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
    return [chapter.Passage(p["idx"], p["text"], bonsai.Tag(**p["tag"]), p["category"], p.get("cluster"))
            for p in raw]


def cmd_match(args) -> None:
    pj_path = _chapter_dir(args.number) / "passages.json"
    pj = json.loads(pj_path.read_text())
    cl = json.loads((WORK_DIR / "clusters.json").read_text())
    lib = library.load_library(WORK_DIR / "library.json")
    menu = {cid: f"{lab['label']} ({lab['sex']}): {lab['description']}"
            for cid, lab in cl["labels"].items() if lib.get(cid)}
    picks = clusters.assign_clusters([p["text"].strip() for p in pj["passages"]], menu, CHAPTER_CONTEXT)
    usable = {cid: g for cid, g in cl["groups"].items() if lib.get(cid)}
    picks = clusters.enforce_group([p["tag"] for p in pj["passages"]], picks, usable, cl["sizes"])
    for p, cid in zip(pj["passages"], picks):
        p["cluster"] = cid
    pj_path.write_text(json.dumps(pj, ensure_ascii=False, indent=1))
    for p in pj["passages"]:
        lab = cl["labels"].get(p["cluster"] or "", {}).get("label", "-")
        print(f"{p['idx']:3d} {p['tag']['speaker'][:16]:16s} {lab[:30]:30s} {p['text'].strip()[:50]!r}")


def cmd_generate(args) -> None:
    ch = _chapter_dir(args.number)
    lib_path = WORK_DIR / "library.json"
    lib = library.load_library(lib_path) if lib_path.exists() else {}
    entries = json.loads(NAMES_FILE.read_text())
    name_map = {name: e["respelling"] for name, e in entries.items()}
    methods = args.methods.split(",") if args.methods else tts.METHODS
    if any(m != "current" for m in methods) and not lib:
        raise SystemExit("library.json missing: run `voicerefs cluster` before generating matched methods")
    gen_path = ch / "generation.json"
    gen = json.loads(gen_path.read_text()) if gen_path.exists() else {"passages": {}, "names": {}}
    result = tts.generate(_load_passages(args.number), lib, name_map, ch / "audio", methods=methods)
    for idx, by_method in result.items():
        gen["passages"].setdefault(idx, {}).update(by_method)
    gen["names"] = tts.generate_names(entries, ch / "audio")
    gen_path.write_text(json.dumps(gen, ensure_ascii=False, indent=1))
    failed = [(i, m) for i, bm in gen["passages"].items() for m, r in bm.items() if "failed" in r]
    print(f"generated {len(gen['passages'])} passages; {len(failed)} failed: {failed}")


def cmd_page(args) -> None:
    out = Path(args.out)
    index = page.build(_chapter_dir(args.number), NAMES_FILE, VOICES_DIR, out)
    files = sorted(p for p in (out / "audio").iterdir())
    total = sum(p.stat().st_size for p in files) + index.stat().st_size
    print(f"{index}  +{len(files)} audio files, {total / 1e6:.1f} MB")


def cmd_features(args) -> None:
    import numpy as np

    src = WORK_DIR / "source"
    segments = json.loads((src / "segments.json").read_text())
    starts = sorted(int(p.stem) for p in (src / "pieces").glob("*.json"))
    tmp = WORK_DIR / "features-tmp"
    emb, pros, egem = [], [], []
    encode_egemma = clusters.egemma_encoder()
    loaded: dict[int, tuple] = {}
    for n, seg in enumerate(segments):
        piece = max(s for s in starts if s <= seg["start"])
        if piece not in loaded:
            loaded.clear()
            wav = audio.extract(SOURCE_BOOK, piece, PIECE_S + 30, tmp / f"{piece}.wav", rate=clusters.ECAPA_RATE)
            loaded[piece] = audio.read(wav)
            wav.unlink()
        samples, rate = loaded[piece]
        clip = samples[int((seg["start"] - piece) * rate): int((seg["end"] - piece) * rate)]
        if len(clip) < rate // 2:
            clip = np.pad(clip, (0, rate // 2 - len(clip)))
        words = len(seg["text"].split())
        emb.append(clusters.embed(clip, rate))
        egem.append(encode_egemma(clip))
        pros.append(np.append(clusters.prosody(clip, rate), words / max(0.5, seg["end"] - seg["start"])))
        if n % 250 == 0:
            print(f"{n}/{len(segments)}", flush=True)
    np.savez(src / "features.npz", emb=np.array(emb), pros=np.array(pros))
    np.save(src / "emb-egemma.npy", np.array(egem))
    print(f"wrote features for {len(segments)} segments")


def main() -> None:
    parser = argparse.ArgumentParser(prog="voicerefs")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("source", help="transcribe stretches of the source audiobook")
    p.add_argument("--stretches", required=True, help="start:duration seconds, comma separated")
    p.set_defaults(func=cmd_source)
    p = sub.add_parser("tag-source", help="tag source segments with bonsai")
    p.set_defaults(func=cmd_tag_source)
    p = sub.add_parser("features", help="voice embedding + prosody for every source segment")
    p.set_defaults(func=cmd_features)
    p = sub.add_parser("cluster", help="cluster source segments by sound, label clusters, cut reference clips")
    p.add_argument("--min-size", type=int, default=40, help="about this many segments per sub-cluster")
    p.add_argument("--max-k", type=int, default=4, help="most sub-clusters per group")
    p.add_argument("--per-cluster", type=int, default=2)
    p.set_defaults(func=cmd_cluster)
    p = sub.add_parser("match", help="assign each passage of a chapter a voice cluster")
    p.add_argument("--number", type=int, default=195)
    p.set_defaults(func=cmd_match)
    for name, func, help_ in (("chapter", cmd_chapter, "tag a chapter and build passages"),
                              ("names", cmd_names, "extract the chapter's names into the book's name list")):
        p = sub.add_parser(name, help=help_)
        p.add_argument("--number", type=int, default=195, help="readaloud chapter number (195 = Chapter 944)")
        p.set_defaults(func=func)
    p = sub.add_parser("generate", help="generate passage audio for each method, plus name samples")
    p.add_argument("--number", type=int, default=195)
    p.add_argument("--methods", default="", help="comma separated subset of current,matched,matched_names")
    p.set_defaults(func=cmd_generate)
    p = sub.add_parser("page", help="build the comparison page")
    p.add_argument("--number", type=int, default=195)
    p.add_argument("--out", default=str(WORK_DIR / "site"))
    p.set_defaults(func=cmd_page)
    args = parser.parse_args()
    args.func(args)
