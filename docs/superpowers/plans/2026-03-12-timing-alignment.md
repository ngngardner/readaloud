# Word Timing Alignment Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align Whisper word timings to source text so highlighting indices match the original chapter words, eliminating drift when Whisper tokenizes differently.

**Architecture:** New `TimingAligner` module in `readaloud_audiobook` uses Elixir's built-in `List.myers_difference/2` to diff normalized word sequences between source text and Whisper output, then maps timings through the diff operations. Integrated into `GenerateJob.synthesize_chunks/3` right after transcription, before offset adjustment.

**Tech Stack:** Elixir stdlib only (`List.myers_difference/2`, `Regex`, `String`). No new dependencies.

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `apps/readaloud_audiobook/lib/readaloud_audiobook/timing_aligner.ex` | Align Whisper timings to source text via Myers diff |
| Create | `apps/readaloud_audiobook/test/readaloud_audiobook/timing_aligner_test.exs` | Unit tests for alignment logic |
| Modify | `apps/readaloud_audiobook/lib/readaloud_audiobook/generate_job.ex:67-78` | Wire alignment into chunk processing |

---

## Chunk 1: TimingAligner Module

### Task 1: Write failing tests for TimingAligner

**Files:**
- Create: `apps/readaloud_audiobook/test/readaloud_audiobook/timing_aligner_test.exs`

- [ ] **Step 1: Write test file with core test cases**

```elixir
defmodule ReadaloudAudiobook.TimingAlignerTest do
  use ExUnit.Case, async: true

  alias ReadaloudAudiobook.TimingAligner

  describe "align/2 — exact match" do
    test "passes through timings when words match exactly" do
      source = "Hello world"
      timings = [
        %{word: "Hello", start_ms: 0, end_ms: 300},
        %{word: "world", start_ms: 300, end_ms: 600}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 2
      assert Enum.at(result, 0).word == "Hello"
      assert Enum.at(result, 0).start_ms == 0
      assert Enum.at(result, 1).word == "world"
      assert Enum.at(result, 1).start_ms == 300
    end
  end

  describe "align/2 — Whisper splits a word" do
    test "merges split word timings (slidin + G → sliding)" do
      source = "reaching up and sliding her chalk"
      timings = [
        %{word: "reaching", start_ms: 0, end_ms: 400},
        %{word: "up", start_ms: 400, end_ms: 600},
        %{word: "and", start_ms: 600, end_ms: 800},
        %{word: "slidin", start_ms: 800, end_ms: 1100},
        %{word: "G", start_ms: 1100, end_ms: 1200},
        %{word: "her", start_ms: 1200, end_ms: 1400},
        %{word: "chalk", start_ms: 1400, end_ms: 1700}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 6
      words = Enum.map(result, & &1.word)
      assert words == ["reaching", "up", "and", "sliding", "her", "chalk"]

      # "sliding" should span from "slidin" start to "G" end
      sliding = Enum.at(result, 3)
      assert sliding.start_ms == 800
      assert sliding.end_ms == 1200

      # Words after the merge should still be correct
      assert Enum.at(result, 4).word == "her"
      assert Enum.at(result, 4).start_ms == 1200
    end
  end

  describe "align/2 — Whisper merges words" do
    test "handles Whisper merging two source words into one" do
      source = "good bye friend"
      timings = [
        %{word: "goodbye", start_ms: 0, end_ms: 500},
        %{word: "friend", start_ms: 500, end_ms: 800}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 3
      words = Enum.map(result, & &1.word)
      assert words == ["good", "bye", "friend"]

      # "good" and "bye" should split the "goodbye" timing proportionally
      good = Enum.at(result, 0)
      bye = Enum.at(result, 1)
      assert good.start_ms == 0
      assert good.end_ms == bye.start_ms
      assert bye.end_ms <= 500
    end
  end

  describe "align/2 — Whisper skips a word" do
    test "interpolates timing for word Whisper missed" do
      source = "the quick brown fox"
      timings = [
        %{word: "the", start_ms: 0, end_ms: 200},
        %{word: "quick", start_ms: 200, end_ms: 500},
        # "brown" missing
        %{word: "fox", start_ms: 700, end_ms: 1000}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 4
      words = Enum.map(result, & &1.word)
      assert words == ["the", "quick", "brown", "fox"]

      brown = Enum.at(result, 2)
      assert brown.start_ms >= 500
      assert brown.end_ms <= 700
    end
  end

  describe "align/2 — Whisper adds extra words" do
    test "ignores extra Whisper words not in source" do
      source = "hello world"
      timings = [
        %{word: "uh", start_ms: 0, end_ms: 100},
        %{word: "hello", start_ms: 100, end_ms: 400},
        %{word: "world", start_ms: 400, end_ms: 700}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 2
      words = Enum.map(result, & &1.word)
      assert words == ["hello", "world"]
    end
  end

  describe "align/2 — punctuation normalization" do
    test "matches words ignoring punctuation differences" do
      source = "Hello, world! How's it going?"
      timings = [
        %{word: "Hello", start_ms: 0, end_ms: 300},
        %{word: "world", start_ms: 300, end_ms: 600},
        %{word: "How's", start_ms: 600, end_ms: 900},
        %{word: "it", start_ms: 900, end_ms: 1050},
        %{word: "going", start_ms: 1050, end_ms: 1300}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 5
      # Source words preserve original punctuation
      assert Enum.at(result, 0).word == "Hello,"
      assert Enum.at(result, 1).word == "world!"
    end
  end

  describe "align/2 — em/en-dash splitting" do
    test "splits words around em-dashes to match Whisper" do
      source = "ours\u2014a long time"
      timings = [
        %{word: "ours", start_ms: 0, end_ms: 300},
        %{word: "a", start_ms: 300, end_ms: 400},
        %{word: "long", start_ms: 400, end_ms: 600},
        %{word: "time", start_ms: 600, end_ms: 900}
      ]

      result = TimingAligner.align(timings, source)

      assert length(result) == 4
      words = Enum.map(result, & &1.word)
      assert words == ["ours", "a", "long", "time"]
    end
  end

  describe "align/2 — edge cases" do
    test "returns empty list for empty source" do
      assert TimingAligner.align([%{word: "hi", start_ms: 0, end_ms: 100}], "") == []
    end

    test "returns empty list for empty timings" do
      assert TimingAligner.align([], "hello world") == []
    end

    test "handles single word" do
      result = TimingAligner.align([%{word: "hello", start_ms: 0, end_ms: 500}], "hello")
      assert length(result) == 1
      assert hd(result).word == "hello"
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/noah/projects/readaloud && mix test apps/readaloud_audiobook/test/readaloud_audiobook/timing_aligner_test.exs`
Expected: Compilation error — `TimingAligner` module not found

---

### Task 2: Implement TimingAligner

**Files:**
- Create: `apps/readaloud_audiobook/lib/readaloud_audiobook/timing_aligner.ex`

- [ ] **Step 1: Write the TimingAligner module**

```elixir
defmodule ReadaloudAudiobook.TimingAligner do
  @moduledoc """
  Aligns Whisper STT word timings to source text using Myers diff.

  Whisper may tokenize words differently from the original text (e.g.,
  splitting "sliding" into "slidin" + "G", merging "good bye" into
  "goodbye", or inserting filler words like "uh"). This module diffs
  the normalized word sequences and maps timings accordingly, producing
  one timing entry per source word.

  Ported from monorepo ep-ln-audiobook AlignmentService.
  """

  @doc """
  Align STT word timings to source text.

  Returns a list of timing maps with `:word`, `:start_ms`, `:end_ms`,
  one per word in the source text.
  """
  def align(_timings, ""), do: []
  def align([], _source), do: []

  def align(timings, source) do
    source_words = tokenize(source)
    stt_words = Enum.map(timings, & &1.word)

    source_norm = Enum.map(source_words, &normalize/1)
    stt_norm = Enum.map(stt_words, &normalize/1)

    ops = List.myers_difference(source_norm, stt_norm)

    preliminary = build_preliminary(ops, source_words, timings)
    interpolate_missing(preliminary, timings)
  end

  # -- Tokenization --

  defp tokenize(text) do
    text
    |> String.replace(~r/[\x{2014}\x{2013}]/, " ")
    |> String.split(~r/\s+/, trim: true)
  end

  defp normalize(word) do
    word
    |> String.downcase()
    |> String.replace(~r/[^\w]/, "")
  end

  # -- Build preliminary mapping from diff ops --

  defp build_preliminary(ops, source_words, timings) do
    {result, _src_idx, _stt_idx} =
      Enum.reduce(ops, {[], 0, 0}, fn {tag, words}, {acc, src_i, stt_i} ->
        case tag do
          :eq ->
            count = length(words)
            entries =
              for i <- 0..(count - 1) do
                {Enum.at(source_words, src_i + i), Enum.at(timings, stt_i + i)}
              end
            {acc ++ entries, src_i + count, stt_i + count}

          :del ->
            # Source words not in STT — mark as unmatched
            count = length(words)
            entries =
              for i <- 0..(count - 1) do
                {Enum.at(source_words, src_i + i), nil}
              end
            {acc ++ entries, src_i + count, stt_i}

          :ins ->
            # Extra STT words — skip them (absorbed by neighbors)
            count = length(words)
            {acc, src_i, stt_i + count}
        end
      end)

    result
  end

  # -- Interpolate missing timings --

  defp interpolate_missing(preliminary, timings) do
    audio_start = if timings != [], do: hd(timings).start_ms, else: 0
    audio_end = if timings != [], do: List.last(timings).end_ms, else: 0

    preliminary
    |> chunk_by_matched()
    |> Enum.flat_map(fn
      {:matched, entries} ->
        Enum.map(entries, fn {source_word, timing} ->
          %{word: source_word, start_ms: timing.start_ms, end_ms: timing.end_ms}
        end)

      {:unmatched, entries, prev_end, next_start} ->
        words = Enum.map(entries, fn {w, _} -> w end)
        prev_end = prev_end || audio_start
        next_start = next_start || audio_end
        # Guard against bad timestamps
        next_start = max(next_start, prev_end)
        distribute_time(words, prev_end, next_start)
    end)
  end

  defp chunk_by_matched(preliminary) do
    {chunks, current_type, current_items, _idx} =
      Enum.reduce(preliminary, {[], nil, [], 0}, fn {_word, timing} = entry, {chunks, type, items, idx} ->
        new_type = if timing, do: :matched, else: :unmatched

        if type == new_type or type == nil do
          {chunks, new_type, items ++ [entry], idx + 1}
        else
          {chunks ++ [{type, items, idx - length(items)}], new_type, [entry], idx + 1}
        end
      end)

    all_chunks = if current_items != [], do: chunks ++ [{current_type, current_items, 0}], else: chunks

    # Annotate unmatched chunks with bounding timestamps
    Enum.map(all_chunks, fn
      {:matched, entries, _start_idx} ->
        {:matched, entries}

      {:unmatched, entries, _start_idx} ->
        # Find prev_end and next_start from the full preliminary list
        first_unmatched_idx = Enum.find_index(preliminary, fn e -> e == hd(entries) end)
        last_unmatched_idx = first_unmatched_idx + length(entries) - 1

        prev_end =
          if first_unmatched_idx > 0 do
            {_, prev_timing} = Enum.at(preliminary, first_unmatched_idx - 1)
            if prev_timing, do: prev_timing.end_ms, else: nil
          else
            nil
          end

        next_start =
          Enum.find_value((last_unmatched_idx + 1)..(length(preliminary) - 1)//1, fn j ->
            {_, t} = Enum.at(preliminary, j)
            if t, do: t.start_ms, else: nil
          end)

        {:unmatched, entries, prev_end, next_start}
    end)
  end

  defp distribute_time(words, start_ms, end_ms) do
    total_chars = words |> Enum.map(&String.length/1) |> Enum.sum() |> max(1)
    available = end_ms - start_ms

    {entries, _} =
      Enum.map_reduce(words, start_ms, fn word, current ->
        char_count = max(String.length(word), 1)
        duration = available * char_count / total_chars
        entry = %{word: word, start_ms: current, end_ms: current + duration}
        {entry, current + duration}
      end)

    entries
  end
end
```

- [ ] **Step 2: Run tests**

Run: `cd /home/noah/projects/readaloud && mix test apps/readaloud_audiobook/test/readaloud_audiobook/timing_aligner_test.exs --trace`
Expected: All tests pass

- [ ] **Step 3: Fix any failing tests, iterate until green**

- [ ] **Step 4: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_audiobook/lib/readaloud_audiobook/timing_aligner.ex \
       apps/readaloud_audiobook/test/readaloud_audiobook/timing_aligner_test.exs
git commit -m "feat: add TimingAligner for Whisper-to-source word alignment

Port of ln-reader AlignmentService using Elixir's List.myers_difference.
Handles word splits, merges, insertions, deletions, and punctuation."
```

---

## Chunk 2: Integration into GenerateJob

### Task 3: Wire TimingAligner into GenerateJob

**Files:**
- Modify: `apps/readaloud_audiobook/lib/readaloud_audiobook/generate_job.ex:67-78`

- [ ] **Step 1: Add alias and modify synthesize_chunks**

In `generate_job.ex`, add the alias at the top (line 6):

```elixir
alias ReadaloudAudiobook.{AudiobookTask, ChapterAudio, TimingAligner}
```

Then replace the chunk_timings assignment (lines 67-78) with:

```elixir
          # Transcribe and align to source text
          chunk_timings =
            case ReadaloudTTS.transcribe(chunk_audio) do
              {:ok, t} ->
                aligned = TimingAligner.align(t, chunk)
                # Offset timings by accumulated audio duration
                Enum.map(aligned, fn w ->
                  %{w | start_ms: w.start_ms + offset_ms, end_ms: w.end_ms + offset_ms}
                end)

              {:error, reason} ->
                Logger.warning("Transcription failed for chunk #{idx}: #{inspect(reason)}")
                []
            end
```

- [ ] **Step 2: Verify compilation**

Run: `cd /home/noah/projects/readaloud && mix compile --warnings-as-errors`
Expected: Compiles clean

- [ ] **Step 3: Run existing tests to verify no regressions**

Run: `cd /home/noah/projects/readaloud && mix test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
cd /home/noah/projects/readaloud
git add apps/readaloud_audiobook/lib/readaloud_audiobook/generate_job.ex
git commit -m "feat: integrate TimingAligner into audio generation pipeline

Whisper timings are now aligned to source text before storage,
fixing highlight drift when Whisper tokenizes differently."
```

### Task 4: Deploy and verify

- [ ] **Step 1: Push and deploy**

```bash
cd /home/noah/projects/readaloud
git push
ssh root@pylon "cd /root/projects/readaloud && git pull && docker compose up -d --build readaloud"
```

- [ ] **Step 2: Verify container is healthy**

```bash
ssh root@pylon "docker ps --filter name=readaloud --format '{{.Names}} {{.Status}}'"
```

- [ ] **Step 3: Test with the known failing chapter**

Navigate to books/2/read/5 and play the audio. Verify that "reaching up and sliding her chalk" highlights correctly without drift.
