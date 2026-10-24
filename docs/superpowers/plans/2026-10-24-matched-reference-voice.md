# Matched Reference Voice Comparison Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone pipeline that generates Reverend Insanity ch. 946 three ways (current clip / matched HWFWM clip / matched clip + Mandarin names), then publish a passage-by-passage comparison page.

**Architecture:** A uv Python package at `tools/voice-refs/` with small modules (whisper, bonsai, laya, clips, passages, names, tts, page) and one CLI with a subcommand per pipeline stage. Every stage reads and writes JSON/WAV under a work dir, so stages are resumable and inspectable. Live services: LocalAI (Breeze, Whisper via LiteLLM), bonsai-text llama-server, laya in-process.

**Tech Stack:** Python 3.10+ via uv, httpx, numpy, soundfile, laya (pip), pytest, ffmpeg/ffprobe CLI.

**Spec:** `docs/superpowers/specs/2026-10-24-matched-reference-voice-design.md`

## Global Constraints

- Never modify readaloud's live app, DB, or chapter audio (pylon `/var/lib/readaloud/data`). Read only.
- Whisper only via LiteLLM: `POST http://pylon:4100/v1/audio/transcriptions`, `model=whisper`, `response_format=verbose_json`, `timestamp_granularities[]=word`, bearer `$LITELLM_MASTER_KEY`. Never start a local whisper.
- Breeze contract: `POST http://phanteks:8090/v1/audio/speech` with `{"model":"breeze-tts-2","input":text,"voice":"/models/voices/<file>.wav","params":{"reference_text":...,"seed":"42","text_chunk_size":"2000"}}`. Never send `speed`. Max 400 chars per request.
- Level every generated chunk to -20 dBFS (RMS), like readaloud `Loudness`.
- Reference clips: 24 kHz mono 16-bit WAV, 6–15 s, exact transcript in a sibling `.txt`; written to `/internalmedia/localai-models/voices/hwfwm-<category>-<n>.wav`. Never overwrite `heath-miller.wav`.
- Scratch/work dir: `/internalmedia/voice-refs-work/` (root disk has filled before; don't put audio on `/`).
- Bonsai: `http://127.0.0.1:18120/v1/chat/completions` (`systemctl --user start bonsai-text`), JSON-schema response format, `temperature: 0.3`, `chat_template_kwargs: {"enable_thinking": false}`.
- Stop `gameassets-tagger-gpu0.timer` and `gameassets-tagger-gpu1.timer` before starting bonsai-text; start them again when the pipeline is done.
- Names target standard Mandarin readings.
- Page audio is Opus or MP3; each file ≤15 MB, each publish ≤64 MB.

## Review Focus

- A name that is a prefix of another ("Hei Cheng" / "Hei Lou Lan", "Fang" / "Fang Yuan") or appears possessive ("Hei Lou Lan's"): longest match wins, possessive kept. → Task 1 test.
- Breeze returns 5xx or times out on one chunk: retry twice, then record that passage/method as failed and continue; the page shows "generation failed" instead of the run aborting. → Task 6 test.
- Bonsai returns invalid JSON or skips/duplicates unit indices: validate, retry once, then fall back to `narration/unknown/calm` for the missing units. → Task 3 test.
- A category with no clip that passed screening: matched methods fall back to `heath-miller.wav` and the page says so. → Task 4 test.
- Dialogue unit containing typographic quotes, em dashes, ellipses, or a quote spanning two paragraphs: splitting keeps the text byte-identical when units are rejoined. → Task 1 test.

---

### Task 1: Package scaffold, chapter text → units, passages, name substitution

**Files:**
- Create: `tools/voice-refs/pyproject.toml`, `tools/voice-refs/voicerefs/__init__.py`, `voicerefs/config.py`, `voicerefs/textunits.py`, `voicerefs/names.py`
- Test: `tools/voice-refs/tests/test_textunits.py`, `tests/test_names.py`

**Interfaces:**
- Produces:
  - `config.py`: constants `WORK_DIR`, `VOICES_DIR="/internalmedia/localai-models/voices"`, `CONTAINER_VOICES="/models/voices"`, `BREEZE_URL`, `LITELLM_URL`, `BONSAI_URL`, `MAX_CHARS=400`, `TARGET_DBFS=-20.0`, `CATEGORIES=["female_calm","female_intense","male_casual","male_intense","narration_action","narration_calm"]`, `FALLBACK_REF=("heath-miller.wav", <its transcript>)`.
  - `textunits.html_to_paragraphs(html: str) -> list[str]`: strip tags, unescape entities, drop empty lines and the "Translator:/Editor:" header lines.
  - `textunits.split_units(paragraphs: list[str]) -> list[Unit]`, `Unit = dataclass(idx:int, para:int, text:str, quoted:bool)`. A unit is one quoted span or one run of unquoted text between quotes, within a paragraph (quote chars `“”"`).
  - `textunits.chunk(text: str, max_chars: int = 400) -> list[str]`: same rule as readaloud `TextChunker`: break at the last sentence end in the window, else `;`/`:`, else comma, else whitespace.
  - `names.apply_names(text: str, mapping: dict[str, str]) -> str`.

- [ ] **Step 1: Write failing tests**

```python
def test_units_rejoin_exactly():
    paras = ['Hei Lou Lan said: “Father… you abandoned me—again.” She smiled.']
    units = split_units(paras)
    assert "".join(u.text for u in units) == paras[0]
    assert [u.quoted for u in units] == [False, True, False]

def test_chunk_respects_limit_and_sentences():
    text = ("Fang Yuan nodded. " * 40).strip()
    parts = chunk(text, 400)
    assert all(len(p) <= 400 for p in parts)
    assert all(p.endswith(".") for p in parts)
    assert " ".join(parts) == text

def test_names_longest_first_and_possessive():
    m = {"Hei Lou Lan": "Hay Low Lahn", "Hei Cheng": "Hay Chung", "Fang": "Fahng", "Fang Yuan": "Fahng Yooen"}
    out = apply_names("Hei Lou Lan's father Hei Cheng met Fang Yuan.", m)
    assert out == "Hay Low Lahn's father Hay Chung met Fahng Yooen."

def test_names_word_boundary():
    assert apply_names("Fangs bared.", {"Fang": "Fahng"}) == "Fangs bared."

def test_html_to_paragraphs_drops_header():
    html = "<p>Chapter 946</p><p>Translator: Atlas Studios</p><p>Hei Lou Lan&rsquo;s eyes</p>"
    assert html_to_paragraphs(html) == ["Chapter 946", "Hei Lou Lan’s eyes"]
```

- [ ] **Step 2: Run** `cd tools/voice-refs && uv run pytest -q` → FAIL (imports missing).
- [ ] **Step 3: Implement** the modules above. `apply_names`: one regex alternation of escaped keys sorted by length descending, wrapped in `\b...\b`.
- [ ] **Step 4: Run** `uv run pytest -q` → all PASS.
- [ ] **Step 5: Commit** `feat(voice-refs): scaffold, text units, name substitution`.

### Task 2: Source audiobook transcription

**Files:**
- Create: `voicerefs/audio.py`, `voicerefs/whisper.py`, `voicerefs/cli.py` (subcommand `source`)
- Test: `tests/test_whisper.py` (with fixture `tests/fixtures/verbose.json`, a small hand-written verbose_json sample)

**Interfaces:**
- Produces:
  - `audio.extract(src: Path, start_s: float, dur_s: float, out: Path, rate: int = 24000) -> Path`: ffmpeg to mono s16 WAV.
  - `audio.rms_dbfs(samples: np.ndarray) -> float`, `audio.level(samples, target_dbfs=-20.0) -> np.ndarray` (clip to [-1, 1]), `audio.read(path) -> (np.ndarray, int)`, `audio.write(path, samples, rate)`.
  - `whisper.transcribe(path: Path) -> list[Segment]`, `Segment = dataclass(start:float, end:float, text:str, avg_logprob:float, no_speech_prob:float, words:list[tuple[str,float,float]])`.
  - `whisper.parse_verbose(js: dict, offset_s: float = 0.0) -> list[Segment]`: tolerant of missing `avg_logprob`/`no_speech_prob` (default 0.0), adds offset.
  - CLI `voicerefs source --stretches 3600:3600,21600:3600,...`: extracts each stretch in 10-min pieces (transcription timeout safety), transcribes, writes `WORK_DIR/source/segments.json` (list of Segment dicts, absolute book times).

- [ ] **Step 1: Write failing tests**: `parse_verbose` on the fixture with `offset_s=600` gives the expected start/end (+600), words, and defaults; `level()` of a sine at -30 dBFS returns RMS within 0.1 dB of -20.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** Use httpx multipart, timeout 600 s.
- [ ] **Step 4: Run** tests → PASS.
- [ ] **Step 5: Live run.** Pick ~4 h of HWFWM spread through the 29 h book (e.g. starts at 1 h, 7 h, 13 h, 19 h, 25 h, 48 min each; builder may adjust toward dialogue-heavy stretches). Run `uv run voicerefs source --stretches ...`. Expected: `segments.json` with thousands of segments; spot-check 3 timestamps by ear-free check: re-transcribe a 10 s cut at one segment's times and confirm the text matches.
- [ ] **Step 6: Commit** code only (not work data) `feat(voice-refs): source transcription`.

### Task 3: Bonsai client and source tagging

**Files:**
- Create: `voicerefs/bonsai.py`, CLI subcommand `tag-source`
- Test: `tests/test_bonsai.py` (mock HTTP with `httpx.MockTransport`)

**Interfaces:**
- Consumes: `Segment` (Task 2).
- Produces:
  - `Tag = dataclass(kind: Literal["narration","dialogue"], speaker: str, sex: Literal["male","female","unknown"], mood: Literal["calm","casual","intense","action"])`.
  - `bonsai.chat_json(system: str, user: str, schema: dict, client: httpx.Client | None = None) -> dict`.
  - `bonsai.tag_units(texts: list[str], context: str, client=None) -> list[Tag]`: sends numbered units (windows of ≤40 units with 5 units of overlap for context), schema requires `{"tags":[{"i":int,"kind":...,"speaker":str,"sex":...,"mood":...}]}`; validates that every index appears exactly once, retries once on invalid output, then fills missing with `Tag("narration","narrator","unknown","calm")`.
  - CLI `tag-source`: tags `segments.json` → `WORK_DIR/source/tagged.json` (segments + tag). Context string says the text is a Whisper transcript of *He Who Fights with Monsters*, narrated by one male narrator doing character voices; quotes may be missing, so infer dialogue from content and attribution.
  - The same `tag_units` is used for the target chapter in Task 5 with a Reverend Insanity context.

- [ ] **Step 1: Failing tests**: (a) valid response → tags in order; (b) first response not JSON, second valid → uses second; (c) both responses missing index 2 → index 2 gets the fallback tag, others kept.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Live run.** Stop the tagger timers, `systemctl --user start bonsai-text`, wait for `/health` 200, run `uv run voicerefs tag-source`. Expected: tagged.json; print counts per (kind, sex, mood); female dialogue count > 0.
- [ ] **Step 6: Commit** `feat(voice-refs): bonsai tagging`.

### Task 4: Clip screening and reference library

**Files:**
- Create: `voicerefs/laya_check.py`, `voicerefs/library.py`, CLI subcommand `library`
- Test: `tests/test_library.py`

**Interfaces:**
- Consumes: tagged segments (Task 3), `audio` (Task 2), `whisper.transcribe`.
- Produces:
  - `library.category_of(tag: Tag) -> str | None`: dialogue+female+calm/casual → `female_calm`; dialogue+female+intense/action → `female_intense`; dialogue+male+calm/casual → `male_casual`; dialogue+male+intense/action → `male_intense`; narration+action/intense → `narration_action`; narration+calm/casual → `narration_calm`; unknown sex dialogue → None.
  - `library.candidates(tagged: list) -> list[Candidate]`: merge consecutive segments with the same category and speaker into spans of 6–15 s (split longer runs at segment boundaries). `Candidate = dataclass(category, speaker, start, end, text, min_avg_logprob, max_no_speech)`.
  - `library.signal_ok(samples, rate) -> bool`: RMS between -35 and -12 dBFS and no internal silence > 1.2 s (start/end trimmed to 0.15 s padding).
  - `laya_check.ask(question: str, text: str) -> float` (probability of yes, loading the model once); screens: "Is this a single speaker talking, with no narration like 'he said' mixed in?" for dialogue, "Is this a complete sentence or more?" for all.
  - `library.select(cands, per_category=3) -> dict[str, list[RefClip]]`: filter `max_no_speech < 0.3`, `min_avg_logprob > -0.6`, `signal_ok`, laya yes-prob ≥ 0.6; rank by laya prob then logprob; prefer distinct speakers.
  - `RefClip = dataclass(category, file, transcript, speaker, start, end)`. The transcript is from re-transcribing the exact cut (not the span text) so it matches the audio. Writes WAV + `.txt` to `VOICES_DIR/hwfwm-<category>-<n>.wav` and `WORK_DIR/library.json`.
  - `library.pick(lib: dict, category: str | None) -> RefClip`: first clip in that category, else `FALLBACK_REF` with `fallback=True`.

- [ ] **Step 1: Failing tests**: `category_of` table above; `candidates` merges three 4 s same-category segments into one 12 s candidate and splits at a category change; `signal_ok` false for a clip with a 2 s silent gap; `pick(lib, "female_calm")` with empty category returns the fallback marked `fallback=True`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Live run** `uv run voicerefs library`. Expected: library.json listing clips for ≥4 of 6 categories; print category → (speaker, duration, transcript) table. Missing categories are reported, not fatal.
- [ ] **Step 6: Commit** `feat(voice-refs): reference clip library`.

### Task 5: Tag the target chapter and build passages; name list

**Files:**
- Create: `voicerefs/chapter.py`, CLI subcommands `chapter`, `names`
- Test: `tests/test_chapter.py`

**Interfaces:**
- Consumes: `textunits` (Task 1), `bonsai.tag_units` (Task 3), `library.category_of` (Task 4), `laya_check.ask`.
- Produces:
  - `Passage = dataclass(idx:int, text:str, tag:Tag, category:str|None)`.
  - `chapter.build_passages(units: list[Unit], tags: list[Tag]) -> list[Passage]`: merge consecutive units with equal `(kind, speaker, sex, mood)` within the same paragraph-run; a new paragraph starts a new passage unless both are narration with the same mood; passages longer than 400 chars stay one passage (TTS chunks them in Task 6).
  - Narration units get one laya call, "Is this passage describing fast physical action or combat?"; yes-prob ≥ 0.7 sets mood `action`.
  - CLI `chapter --src <html>`: fetch `/var/lib/readaloud/data/files/books/12/chapters/0197.html` via `ssh root@pylon cat` (read only), write `WORK_DIR/ch946/passages.json`.
  - CLI `names`: bonsai extracts names from the chapter with schema `{"names":[{"name":str,"hanzi":str,"pinyin":str,"respelling":str}]}` (prompt: standard Mandarin readings; respelling for an English TTS reader so that it sounds like the Mandarin). Writes `tools/voice-refs/names/reverend-insanity.json` (committed; grows per chapter, existing entries preserved).
- [ ] **Step 1: Failing tests**: `build_passages` on units [narration calm, quote Hei Lou Lan female intense, narration calm "she said.", quote Hei Lou Lan female intense] in one paragraph → 4 passages (the attribution unit separates the two quotes) with categories [narration_calm, female_intense, narration_calm, female_intense], and `"".join(p.text for p in passages)` equals the paragraph; two consecutive calm narration paragraphs → 1 passage.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Live run** `chapter` then `names`. Expected: passages.json with Hei Lou Lan passages tagged female; names JSON including Hei Lou Lan, Fang Yuan, Hei Cheng (if present) with hanzi + pinyin. Then stop bonsai-text and start the two tagger timers again.
- [ ] **Step 6: Commit** `feat(voice-refs): chapter passages and name list` (include `names/reverend-insanity.json`).

### Task 6: Generation

**Files:**
- Create: `voicerefs/tts.py`, CLI subcommand `generate`
- Test: `tests/test_tts.py` (MockTransport)

**Interfaces:**
- Consumes: `Passage` (Task 5), `library.pick` / `RefClip` (Task 4), `textunits.chunk`, `names.apply_names`, `audio.level`.
- Produces:
  - `tts.speak(text: str, ref_file: str, ref_text: str, client=None) -> np.ndarray` (24 kHz float): one Breeze request; retries twice on 5xx/timeout (timeout 300 s), then raises `TTSFailed`.
  - `tts.render(text, ref_file, ref_text, client=None) -> np.ndarray`: `chunk(text, 400)` → `speak` → `level(-20)` per chunk → concatenate with 120 ms silence between chunks.
  - CLI `generate`: methods `current` (FALLBACK_REF), `matched` (pick by passage category), `matched_names` (matched ref, `apply_names(text, respelling map)`). Writes `WORK_DIR/ch946/audio/<idx:03d>-<method>.opus` (ffmpeg libopus 48 kbps) and `generation.json` with per passage/method: file or `{"failed": reason}`, ref file, fallback flag. Skips outputs that already exist (resumable).
  - Names section: for each name, the sentence `"<form> nodded slowly."` rendered with FALLBACK_REF in three forms: original spelling, respelling, hanzi → `audio/name-<k>-<form>.opus`.
- [ ] **Step 1: Failing tests**: `speak` retries after two 503s then succeeds; three 503s → `TTSFailed`; the request JSON has no `speed` key and `params.seed == "42"`; `generate` on a passage whose `speak` raises records `{"failed": ...}` and continues to the next passage.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Live run** `uv run voicerefs generate`. Expected: 3 × passage-count opus files (minus reported failures), name samples, total size < 60 MB (`du -sh`).
- [ ] **Step 6: Commit** `feat(voice-refs): passage generation`.

### Task 7: Comparison page and publish

**Files:**
- Create: `voicerefs/page.py`, `voicerefs/page_template.html`, CLI subcommand `page`
- Test: `tests/test_page.py`

**Interfaces:**
- Consumes: `passages.json`, `generation.json`, `library.json`, names JSON.
- Produces:
  - `page.build(work: Path, out_dir: Path) -> Path`: writes `out_dir/index.html` and copies referenced audio (passage audio, the reference clips used, converted to opus, and name samples) into `out_dir/audio/`. Page data is embedded as a JSON `<script>` block.
  - Page (per spec): header with chapter title and the three methods explained in one line each; **Names** section (each name: pinyin, hanzi, three players: original / respelling / hanzi); filter chips by category (at least "female dialogue"); passage list: text, tag line `dialogue · female · Hei Lou Lan · intense`, three labelled players, reference clip player with speaker + "fallback" badge when used, "generation failed" in place of a player when failed. Phone-first layout, light/dark tokens per the artifact contract; load the `artifact-design` skill before writing the template.
- [ ] **Step 1: Failing tests**: `build` on a tiny fixture work dir (2 passages, one failed method, one fallback ref) produces HTML containing both passage texts, one "generation failed" marker, one "fallback" badge, and every `audio/...` path referenced in the HTML exists in `out_dir`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Build and publish** `uv run voicerefs page --out /internalmedia/voice-refs-work/site`; publish with the Artifact tool (`file_path` = index.html, `files` = every audio file, icon `audio`). Open the URL and check one passage per method plays.
- [ ] **Step 6: Commit** `feat(voice-refs): comparison page`.
