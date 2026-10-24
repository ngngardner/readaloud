"""voicerefs: one subcommand per pipeline stage. Every stage reads/writes under WORK_DIR."""

import argparse
import json
from dataclasses import asdict

from . import audio, whisper
from .config import SOURCE_BOOK, WORK_DIR

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


def main() -> None:
    parser = argparse.ArgumentParser(prog="voicerefs")
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("source", help="transcribe stretches of the source audiobook")
    p.add_argument("--stretches", required=True, help="start:duration seconds, comma separated")
    p.set_defaults(func=cmd_source)
    args = parser.parse_args()
    args.func(args)
