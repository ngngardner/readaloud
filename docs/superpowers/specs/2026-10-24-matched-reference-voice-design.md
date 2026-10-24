# Matched reference clips for the breeze voice: comparison experiment

Date: 2026-10-24
Status: approved by Noah 2026-10-24

## Why

Reverend Insanity is read by `breeze-tts-2` / `heath-miller`: a clone of
Heath Miller, narrator of the *He Who Fights with Monsters* (HWFWM)
audiobook. Noah likes the intonation, but every chunk is conditioned on
the same 9.7 s clip of calm male narration, so every line inherits that
register. The concrete failure Noah heard: **a female character came out
with a brutish, deep male sound.**

Heath Miller does character voices in HWFWM. If, for each passage of the
target text, we hand Breeze a reference clip of him doing the *same kind
of speech* (female dialogue, male dialogue, action narration, calm
narration, ...), the clone should pick up that register instead.

Separately, Chinese names in Reverend Insanity are pronounced badly and
inconsistently. That is not a reference-clip problem, but Noah asked for
it to be included in the same comparison.

## What gets delivered

A private claude.ai Artifact page (openable on Noah's phone) comparing
generation methods **passage by passage** on one chapter.

- Test chapter: **Reverend Insanity, Chapter 946 "Past Grudges and Hatred"**
  (readaloud book 12, chapter `number` 197, content
  `/var/lib/readaloud/data/files/books/12/chapters/0197.html` on pylon).
  Noah's current chapter, heavy on Hei Lou Lan dialogue. (It was not the
  exact chapter where the bad female voice stood out, but Noah said it's fine.)
- The chapter is shown as a list of passages. Each passage shows:
  - its text
  - the tags it was given (e.g. `dialogue · female · Hei Lou Lan · angry`)
  - one player per method, labelled by method name (not a blind test)
  - a player for the reference clip the matched methods used, so Noah can
    tell whether a bad result came from the clip or from the model
- A filter to show only passages of a given kind (at minimum: female
  dialogue, since that's the reported failure).

Methods, all reading the identical passage text:

1. **Current**: fixed `heath-miller.wav` reference, as readaloud does today.
2. **Matched clip**: a reference cut from HWFWM matching the passage's tags.
3. **Matched clip + names**: as 2, with the book's name pronunciation list
   applied to the text first.

Noah confirmed this picture of the site ("That's right").

## Goals

- Let Noah judge by ear, on real text, whether matched references fix
  female (and other) character voices without losing breeze's intonation.
- Let Noah judge whether a fixed per-book name pronunciation list makes
  names correct (Mandarin) and consistent.
- Produce the reusable pieces (reference library, tagging prompts, name
  list) in a form readaloud could adopt later if the experiment wins.

## Non-goals

- No changes to readaloud's live generation, DB, or stored chapter audio.
  The existing chapter 946 audio stays untouched.
- No readaloud UI. The comparison page is standalone.
- Not fixing chunk-seam consistency (see the Oct 2026 seam work); not
  re-picking the TTS model.
- Not the whole book: one chapter.

## Anti-goals (failure even if it "works")

- Matched clips that make *every* voice sound like a different narrator,
  losing what Noah likes about the clone.
- Names that are consistent but consistently wrong.
- Touching Noah's live Reverend Insanity audio.

## How it works

### 1. Reference library from the source audiobook

- Source: `/mnt/gardnerstorage/Media/Audiobooks/Shirtaloon/He Who Fights with Monsters/Shirtaloon - He Who Fights with Monsters.m4b`
  (29 h, mounted on phanteks). There is no ebook text and no saved
  transcript of it; the original clip's transcript work is gone.
- Transcribe a few hours of it (builder's call which stretches; pick ones
  rich in dialogue with female characters) with LocalAI Whisper via LiteLLM
  (`whisper`, `verbose_json`, word timestamps). **Do not** start a separate
  local whisper (user rule: fix the gateway, don't route around it).
- Bonsai tags each speech stretch: narration vs dialogue, speaker (named
  character where inferable), speaker sex, mood.
- Screening candidate clips: laya reads text only, so it screens the
  *transcript* (one speaker, a complete utterance, no dialogue tag like
  "she said" inside a dialogue clip). Audio cleanliness is checked from
  the audio side: Whisper `no_speech_prob` / `avg_logprob` plus a simple
  signal check (level and silence) to catch music or crosstalk. Length is
  checked in code. The page plays every reference clip, so Noah can hear a
  bad clip for himself. *(My call.)*
- Select a few clips per category. Starting categories (from Noah's list
  plus my guesses): female calm, female angry/intense, male casual, male
  gruff/angry, action narration, calm narration. Builder may add or merge
  categories based on what the source actually contains.
- Clips: 24 kHz mono 16-bit WAV, roughly 6–15 s (the current clip is 9.7 s),
  each with an exact transcript (Breeze needs `reference_text`). Place them
  in `/internalmedia/localai-models/voices/` (= `/models/voices/` inside the
  LocalAI container) under a distinct prefix so they don't collide with
  `heath-miller.wav`.

### 2. Tag the target chapter

- Bonsai splits chapter 946 into passages at every speaker change and
  attributes each dialogue passage to a speaker (resolving "she said"
  across lines), then tags sex and mood. Laya takes the simpler calls
  (e.g. "is this high action?").
- Long narration still gets split to stay under readaloud's 400-character
  Breeze chunk limit; a passage may therefore be several requests.

### 3. Generate

- Breeze via LocalAI on phanteks: `POST http://phanteks:8090/v1/audio/speech`,
  same contract as readaloud (`apps/readaloud_tts/lib/readaloud_tts/local_ai_provider.ex:76-106`):
  `voice` = container WAV path, `params.reference_text`, `params.seed: "42"`,
  `params.text_chunk_size: "2000"`, never `speed`. Level each chunk to
  -20 dBFS like readaloud's `Loudness`.
- Method 1 uses the same passage boundaries as methods 2/3 so that the
  reference (and, for 3, the names) is the only difference. *(My call.)*
- Matched methods pick the closest category clip; if nothing matches
  well, fall back to the current narration clip.

### 4. Name pronunciation

- **Correct means Mandarin** (Noah's answer): the target is the standard
  Mandarin reading of each name, not an anglicised reading. Tones are
  nice to have; getting the initials and finals right (x, q, zh, c, ui,
  ou...) is the bar.
- Bonsai extracts every Chinese name in the chapter and proposes a
  pronunciation the model reads correctly; the same substitution is applied
  every time the name appears.
- Two candidate forms: an English respelling that approximates the
  Mandarin ("Hei Lou Lan" → "Hay Low Lahn", "Xie" → "Shyeh") and the Hanzi (Breeze is from MediaTek and speaks
  Mandarin, so 黑楼兰 might be read natively, though it may switch accent
  mid-sentence, and bonsai must guess characters from the English
  translation). The builder can't hear audio, so the page gets a small
  **Names** section at the top: each name spoken in a short sentence in
  both forms, for Noah to pick from. Method 3 uses the respelling. *(My
  call.)*
- The list is stored per book (a plain JSON/TOML file) so it can grow
  chapter by chapter later.

### Models and where they run

- **Bonsai**: Ternary-Bonsai-2-27B, llama-server (PrismML fork) on
  phanteks, OpenAI-compatible `/v1/chat/completions`. The text-only unit is
  `bonsai-text` on `127.0.0.1:18120` (configs `nix/services/modules/gameassets/default.nix:196-217`);
  currently inactive, start it for this work. GPU 1 has room
  (GPU 0 holds LocalAI). Use JSON-schema response format, as
  `gameassets/svc/bonsai.py` does.
- `bonsai-text` has `Conflicts=gameassets-bonsai-gpu1.service`, and the
  hourly gameassets tagger timers (both GPUs) would start that unit and
  kill `bonsai-text` mid-job. Stop the tagger timers (`systemctl --user
  stop`) for the duration of the run and start them again afterwards.
  Runtime only, no config change. *(My call.)*
- **Laya**: `convaiinnovations/laya`, ModernBERT classifier. Not served
  anywhere; run it in-process from Python (`pip install laya`, as
  bloons-blitz does). It answers typed yes/no or choice questions with
  probabilities.
- Noah's split: bonsai for working out who is talking, laya for simple
  decisions.

### Change 2026-10-24 (Noah): clusters replace the fixed categories

The narrator may have more delivery types than the six fixed categories
(e.g. HWFWM's system-message voice). So the reference library is built
by clustering the source segments on their *audio* (an ECAPA voice
embedding plus pitch level/range, loudness and speaking rate), choosing
the number of clusters from the data. Bonsai labels each cluster from
sample lines, their tags and the prosody summary. For each target
passage bonsai picks the best-fitting cluster, and the reference clip
comes from that cluster's cleanest, most central segments. This replaces
the fixed-category clip choice for methods 2 and 3 (not an extra method).
The bonsai tags from step 1 are kept as input to cluster labelling.

## Constraints

- Work on phanteks; readaloud runs on pylon and is not touched.
- phanteks' root disk has hit 0 bytes before in TTS work: keep scratch
  audio on a data disk, clean up intermediates.
- LocalAI GPU 0 is shared with live readaloud generation; don't evict it.
- Artifact limits: 15 MB per binary file, 64 MB per publish. Use a
  compressed format (Opus or MP3) for page audio.

## Where the code lives

`tools/voice-refs/` in the readaloud repo, Python with uv (scripts for
transcribe → tag → select → generate → build page). Not wired into the
Elixir app. *(My call.)*

## Left to the builder

- Which HWFWM stretches to transcribe, and how many hours.
- Exact category set and how many clips per category.
- Prompts and schemas for bonsai and laya.
- Page layout and styling within the description above.
