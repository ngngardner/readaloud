"""Build the comparison page: index.html with embedded data, plus the audio it plays."""

import json
import shutil
import subprocess
from pathlib import Path

from .bonsai import Tag
from .tts import METHODS

TEMPLATE = Path(__file__).with_name("page_template.html")
METHOD_LABELS = {
    "current": "Current",
    "matched": "Matched clip",
    "matched_names": "Matched + names",
}


def _ref_audio(ref: dict, voices_dir: Path, out_audio: Path, cache: dict[str, str]) -> str:
    file = ref["file"]
    if file not in cache:
        dest = out_audio / ("ref-" + Path(file).stem + ".opus")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(voices_dir / file), "-c:a", "libopus", "-b:a", "48k",
                        str(dest)], check=True)
        cache[file] = f"audio/{dest.name}"
    return cache[file]


def _copy(src_dir: Path, name: str, out_audio: Path) -> str:
    shutil.copyfile(src_dir / name, out_audio / name)
    return f"audio/{name}"


def build(chapter_dir: Path, names_path: Path, voices_dir: Path, out_dir: Path,
          clusters_path: Path | None = None, library_path: Path | None = None) -> Path:
    out_audio = out_dir / "audio"
    out_audio.mkdir(parents=True, exist_ok=True)
    src_audio = chapter_dir / "audio"
    passages = json.loads((chapter_dir / "passages.json").read_text())
    gen = json.loads((chapter_dir / "generation.json").read_text())
    entries = json.loads(names_path.read_text())
    ref_cache: dict[str, str] = {}

    rows = []
    for p in passages["passages"]:
        by_method = gen["passages"].get(str(p["idx"]), {})
        methods = {}
        for m in METHODS:
            rec = by_method.get(m)
            if rec is None:
                continue
            ref = dict(rec["ref"])
            ref["audio"] = _ref_audio(ref, voices_dir, out_audio, ref_cache)
            entry = {"label": METHOD_LABELS[m], "text": rec["text"], "ref": ref}
            if "failed" in rec:
                entry["failed"] = rec["failed"]
            else:
                entry["file"] = _copy(src_audio, rec["file"], out_audio)
            methods[m] = entry
        tag = Tag(**p["tag"])
        rows.append({"idx": p["idx"], "text": p["text"], "tag": p["tag"], "category": p["category"],
                     "kind": tag.kind, "methods": methods})

    name_rows = []
    for name, files in gen.get("names", {}).items():
        e = entries.get(name, {})
        name_rows.append({"name": name, "hanzi": e.get("hanzi", ""), "pinyin": e.get("pinyin", ""),
                          "respelling": e.get("respelling", ""),
                          "audio": {form: _copy(src_audio, f, out_audio) for form, f in files.items()}})

    voices = []
    if clusters_path and clusters_path.exists() and library_path and library_path.exists():
        cl = json.loads(clusters_path.read_text())
        lib = json.loads(library_path.read_text())
        for cid, lab in cl["labels"].items():
            clips = [{"speaker": c["speaker"], "transcript": c["transcript"], "seconds": round(c["end"] - c["start"], 1),
                      "audio": _ref_audio(c, voices_dir, out_audio, ref_cache)} for c in lib.get(cid, [])]
            voices.append({"id": cid, "group": cl["groups"].get(cid, ""), "segments": cl["sizes"].get(cid, 0),
                           "label": lab["label"], "description": lab.get("description", ""), "clips": clips})

    data = {"title": passages["title"], "methods": METHOD_LABELS, "passages": rows, "names": name_rows,
            "voices": voices}
    blob = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    html = TEMPLATE.read_text().replace("/*__DATA__*/{}", blob)
    index = out_dir / "index.html"
    index.write_text(html)
    return index
