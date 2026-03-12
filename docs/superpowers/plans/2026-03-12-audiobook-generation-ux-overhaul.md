# Audiobook Generation UX Overhaul Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace manual batch-select-and-generate audiobook workflow with automatic, profile-driven generation system.

**Architecture:** Domain function `ensure_audio_generated/2` in `ReadaloudAudiobook` identifies missing/stale chapters and queues generation. `BookLive` calls it on mount and PubSub completion events. `build_audio_map/2` tracks per-chapter status including composite states for stale-but-playable audio. Settings UI is a DaisyUI dropdown popover.

**Tech Stack:** Elixir, Phoenix LiveView, DaisyUI 5, SQLite/Ecto, Oban Lite

**Spec:** `docs/superpowers/specs/2026-03-12-audiobook-generation-ux-overhaul-design.md`

---

## Chunk 1: Schema & Domain Logic

### Task 1: Add migration for new schema fields

**Files:**
- Create: `apps/readaloud_library/priv/repo/migrations/20260312220000_add_audio_profile_tracking.exs`

- [ ] **Step 1: Create the migration file**

```elixir
defmodule ReadaloudLibrary.Repo.Migrations.AddAudioProfileTracking do
  use Ecto.Migration

  def change do
    alter table(:chapter_audios) do
      add :model, :string
      add :voice, :string
    end

    alter table(:audiobook_tasks) do
      add :attempt_number, :integer, default: 1
    end
  end
end
```

- [ ] **Step 2: Run migration**

Run: `cd /home/noah/projects/readaloud && mix ecto.migrate`
Expected: Migration runs successfully, no errors.

- [ ] **Step 3: Commit**

```bash
git add apps/readaloud_library/priv/repo/migrations/20260312220000_add_audio_profile_tracking.exs
git commit -m "feat: add model/voice to chapter_audios and attempt_number to audiobook_tasks"
```

---

### Task 2: Update AudiobookTask schema and changeset

**Files:**
- Modify: `apps/readaloud_audiobook/lib/readaloud_audiobook/audiobook_task.ex`

- [ ] **Step 1: Write the test**

Add to `apps/readaloud_audiobook/test/readaloud_audiobook_test.exs`:

```elixir
describe "AudiobookTask.changeset/2" do
  test "casts attempt_number" do
    changeset = ReadaloudAudiobook.AudiobookTask.changeset(
      %ReadaloudAudiobook.AudiobookTask{},
      %{book_id: 1, scope: "chapter", attempt_number: 2}
    )
    assert changeset.changes[:attempt_number] == 2
  end

  test "attempt_number not cast when not in cast list" do
    # This verifies the field is properly cast (not just using schema default)
    changeset = ReadaloudAudiobook.AudiobookTask.changeset(
      %ReadaloudAudiobook.AudiobookTask{},
      %{book_id: 1, scope: "chapter", attempt_number: 5}
    )
    assert changeset.changes[:attempt_number] == 5
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/noah/projects/readaloud && mix test apps/readaloud_audiobook/test/readaloud_audiobook_test.exs --only describe:"AudiobookTask.changeset/2"`
Expected: FAIL — `attempt_number` not in cast list, changes won't include it.

- [ ] **Step 3: Add `attempt_number` to schema and changeset**

In `apps/readaloud_audiobook/lib/readaloud_audiobook/audiobook_task.ex`:

Add field to schema (after `field :error_message, :string`):
```elixir
field :attempt_number, :integer, default: 1
```

Update cast list in `changeset/2`:
```elixir
|> cast(attrs, [:book_id, :chapter_id, :scope, :voice, :speed, :model, :status, :progress, :error_message, :attempt_number])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/noah/projects/readaloud && mix test apps/readaloud_audiobook/test/readaloud_audiobook_test.exs`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/readaloud_audiobook/lib/readaloud_audiobook/audiobook_task.ex apps/readaloud_audiobook/test/readaloud_audiobook_test.exs
git commit -m "feat: add attempt_number field to AudiobookTask"
```

---

### Task 3: Update ChapterAudio schema and changeset

**Files:**
- Modify: `apps/readaloud_audiobook/lib/readaloud_audiobook/chapter_audio.ex`

- [ ] **Step 1: Write the test**

Add to `apps/readaloud_audiobook/test/readaloud_audiobook_test.exs`:

```elixir
describe "ChapterAudio.changeset/2" do
  test "casts model and voice" do
    changeset = ReadaloudAudiobook.ChapterAudio.changeset(
      %ReadaloudAudiobook.ChapterAudio{},
      %{chapter_id: 1, audio_path: "/tmp/test.wav", model: "kokoro", voice: "af_heart"}
    )
    assert changeset.changes[:model] == "kokoro"
    assert changeset.changes[:voice] == "af_heart"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/noah/projects/readaloud && mix test apps/readaloud_audiobook/test/readaloud_audiobook_test.exs --only describe:"ChapterAudio.changeset/2"`
Expected: FAIL — `model` and `voice` not in cast list.

- [ ] **Step 3: Add `model` and `voice` to schema and changeset**

In `apps/readaloud_audiobook/lib/readaloud_audiobook/chapter_audio.ex`:

Add fields to schema (after `field :word_timings, :string`):
```elixir
field :model, :string
field :voice, :string
```

Update cast list in `changeset/2`:
```elixir
|> cast(attrs, [:chapter_id, :audio_path, :duration_seconds, :word_timings, :model, :voice])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/noah/projects/readaloud && mix test apps/readaloud_audiobook/test/readaloud_audiobook_test.exs`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/readaloud_audiobook/lib/readaloud_audiobook/chapter_audio.ex apps/readaloud_audiobook/test/readaloud_audiobook_test.exs
git commit -m "feat: add model and voice fields to ChapterAudio"
```

---

### Task 4: Update `generate_for_chapter/3` to accept `attempt_number`

**Files:**
- Modify: `apps/readaloud_audiobook/lib/readaloud_audiobook.ex`

- [ ] **Step 1: Write the test**

Add to `apps/readaloud_audiobook/test/readaloud_audiobook_test.exs`:

```elixir
describe "generate_for_chapter/3 with attempt_number" do
  test "passes attempt_number to task", %{book: book, ch1: ch1} do
    assert {:ok, task} = ReadaloudAudiobook.generate_for_chapter(book.id, ch1.id, attempt_number: 2)
    assert task.attempt_number == 2
  end

  test "defaults attempt_number to 1", %{book: book, ch1: ch1} do
    assert {:ok, task} = ReadaloudAudiobook.generate_for_chapter(book.id, ch1.id)
    assert task.attempt_number == 1
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/noah/projects/readaloud && mix test apps/readaloud_audiobook/test/readaloud_audiobook_test.exs --only describe:"generate_for_chapter/3 with attempt_number"`
Expected: FAIL — `attempt_number` not included in attrs map.

- [ ] **Step 3: Add `attempt_number` to attrs in `generate_for_chapter/3`**

In `apps/readaloud_audiobook/lib/readaloud_audiobook.ex`, update `generate_for_chapter/3`:

Replace the `attrs` building block (lines 7-11):
```elixir
    attrs =
      %{book_id: book_id, chapter_id: chapter_id, scope: "chapter"}
      |> maybe_put(:voice, Keyword.get(opts, :voice))
      |> maybe_put(:speed, Keyword.get(opts, :speed))
      |> maybe_put(:model, Keyword.get(opts, :model))
      |> maybe_put(:attempt_number, Keyword.get(opts, :attempt_number))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/noah/projects/readaloud && mix test apps/readaloud_audiobook/test/readaloud_audiobook_test.exs`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/readaloud_audiobook/lib/readaloud_audiobook.ex apps/readaloud_audiobook/test/readaloud_audiobook_test.exs
git commit -m "feat: generate_for_chapter accepts attempt_number option"
```

---

### Task 5: Update GenerateJob to persist model/voice on ChapterAudio

**Files:**
- Modify: `apps/readaloud_audiobook/lib/readaloud_audiobook/generate_job.ex`

- [ ] **Step 1: Update ChapterAudio insert in GenerateJob.perform/1**

In `apps/readaloud_audiobook/lib/readaloud_audiobook/generate_job.ex`, update the `ChapterAudio` changeset call (lines 27-34).

Replace:
```elixir
      %ChapterAudio{}
      |> ChapterAudio.changeset(%{
        chapter_id: chapter.id,
        audio_path: audio_path,
        duration_seconds: calculate_duration(audio),
        word_timings: Jason.encode!(timings)
      })
      |> Repo.insert!(on_conflict: :replace_all, conflict_target: :chapter_id)
```

With:
```elixir
      %ChapterAudio{}
      |> ChapterAudio.changeset(%{
        chapter_id: chapter.id,
        audio_path: audio_path,
        duration_seconds: calculate_duration(audio),
        word_timings: Jason.encode!(timings),
        model: task.model,
        voice: task.voice
      })
      |> Repo.insert!(on_conflict: :replace_all, conflict_target: :chapter_id)
```

- [ ] **Step 2: Verify compilation**

Run: `cd /home/noah/projects/readaloud && mix compile --warnings-as-errors`
Expected: Compiles with no errors or warnings.

- [ ] **Step 3: Run existing tests**

Run: `cd /home/noah/projects/readaloud && mix test apps/readaloud_audiobook/test/`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add apps/readaloud_audiobook/lib/readaloud_audiobook/generate_job.ex
git commit -m "feat: GenerateJob persists model/voice to ChapterAudio on completion"
```

---

### Task 6: Implement `ensure_audio_generated/2`

**Files:**
- Modify: `apps/readaloud_audiobook/lib/readaloud_audiobook.ex`

- [ ] **Step 1: Write the tests**

Add to `apps/readaloud_audiobook/test/readaloud_audiobook_test.exs`:

```elixir
describe "ensure_audio_generated/2" do
  test "returns {:ok, 0} when audio_preferences is nil", %{book: book} do
    chapters = ReadaloudLibrary.list_chapters(book.id)
    assert {:ok, 0} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
  end

  test "queues chapters missing audio", %{book: book, ch1: ch1, ch2: ch2} do
    {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})
    chapters = ReadaloudLibrary.list_chapters(book.id)

    assert {:ok, 2} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)

    tasks = ReadaloudAudiobook.list_tasks()
    assert length(tasks) == 2
    assert Enum.all?(tasks, &(&1.model == "kokoro"))
    assert Enum.all?(tasks, &(&1.voice == "af_heart"))
    assert Enum.all?(tasks, &(&1.attempt_number == 1))
  end

  test "skips chapters with existing matching audio", %{book: book, ch1: ch1, ch2: ch2} do
    {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})

    # Insert matching audio for ch1
    %ReadaloudAudiobook.ChapterAudio{}
    |> ReadaloudAudiobook.ChapterAudio.changeset(%{
      chapter_id: ch1.id, audio_path: "/tmp/test.wav",
      duration_seconds: 60.0, model: "kokoro", voice: "af_heart"
    })
    |> ReadaloudLibrary.Repo.insert!()

    chapters = ReadaloudLibrary.list_chapters(book.id)
    assert {:ok, 1} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
  end

  test "queues chapters with stale audio (different model/voice)", %{book: book, ch1: ch1} do
    {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})

    # Insert audio with old voice
    %ReadaloudAudiobook.ChapterAudio{}
    |> ReadaloudAudiobook.ChapterAudio.changeset(%{
      chapter_id: ch1.id, audio_path: "/tmp/test.wav",
      duration_seconds: 60.0, model: "kokoro", voice: "bf_emma"
    })
    |> ReadaloudLibrary.Repo.insert!()

    chapters = ReadaloudLibrary.list_chapters(book.id)
    assert {:ok, 2} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
  end

  test "skips chapters with pending/processing tasks", %{book: book, ch1: ch1} do
    {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})

    # Create pending task for ch1
    ReadaloudAudiobook.generate_for_chapter(book.id, ch1.id, model: "kokoro", voice: "af_heart")

    chapters = ReadaloudLibrary.list_chapters(book.id)
    # ch1 already has a pending task, only ch2 should be queued
    assert {:ok, 1} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
  end

  test "skips chapters that exceeded failure threshold", %{book: book, ch1: ch1} do
    {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})

    # Insert a failed task at attempt_number 3 for ch1 with matching profile
    %ReadaloudAudiobook.AudiobookTask{}
    |> ReadaloudAudiobook.AudiobookTask.changeset(%{
      book_id: book.id, chapter_id: ch1.id, scope: "chapter",
      model: "kokoro", voice: "af_heart", status: "failed",
      attempt_number: 3, error_message: "permanent failure"
    })
    |> ReadaloudLibrary.Repo.insert!()

    chapters = ReadaloudLibrary.list_chapters(book.id)
    # ch1 is skipped (attempt_number >= 3), only ch2 queued
    assert {:ok, 1} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
  end

  test "resets failure count when profile changes", %{book: book, ch1: ch1} do
    # Failed with old voice
    %ReadaloudAudiobook.AudiobookTask{}
    |> ReadaloudAudiobook.AudiobookTask.changeset(%{
      book_id: book.id, chapter_id: ch1.id, scope: "chapter",
      model: "kokoro", voice: "bf_emma", status: "failed",
      attempt_number: 3, error_message: "permanent failure"
    })
    |> ReadaloudLibrary.Repo.insert!()

    # Switch to different voice
    {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})

    chapters = ReadaloudLibrary.list_chapters(book.id)
    # Both should be queued — old failures don't count for new profile
    assert {:ok, 2} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
  end

  test "is idempotent", %{book: book} do
    {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})
    chapters = ReadaloudLibrary.list_chapters(book.id)

    assert {:ok, 2} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
    # Second call should queue nothing (tasks already pending)
    assert {:ok, 0} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)
  end

  test "increments attempt_number on retry", %{book: book, ch1: ch1} do
    {:ok, book} = ReadaloudLibrary.update_book(book, %{audio_preferences: %{"model" => "kokoro", "voice" => "af_heart"}})

    # Insert a failed task at attempt_number 1
    %ReadaloudAudiobook.AudiobookTask{}
    |> ReadaloudAudiobook.AudiobookTask.changeset(%{
      book_id: book.id, chapter_id: ch1.id, scope: "chapter",
      model: "kokoro", voice: "af_heart", status: "failed",
      attempt_number: 1, error_message: "transient error"
    })
    |> ReadaloudLibrary.Repo.insert!()

    chapters = ReadaloudLibrary.list_chapters(book.id)
    assert {:ok, 2} = ReadaloudAudiobook.ensure_audio_generated(book, chapters)

    # Find the new task for ch1
    tasks = ReadaloudAudiobook.list_tasks()
    ch1_task = Enum.find(tasks, &(&1.chapter_id == ch1.id && &1.status == "pending"))
    assert ch1_task.attempt_number == 2
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/noah/projects/readaloud && mix test apps/readaloud_audiobook/test/readaloud_audiobook_test.exs --only describe:"ensure_audio_generated/2"`
Expected: FAIL — `ensure_audio_generated/2` not defined.

- [ ] **Step 3: Implement `ensure_audio_generated/2`**

Add to `apps/readaloud_audiobook/lib/readaloud_audiobook.ex` (before `list_tasks/0`):

```elixir
  @max_attempts 3

  def ensure_audio_generated(%{audio_preferences: nil}, _chapters), do: {:ok, 0}
  def ensure_audio_generated(%{audio_preferences: prefs}, _chapters) when map_size(prefs) == 0, do: {:ok, 0}

  def ensure_audio_generated(book, chapters) do
    model = book.audio_preferences["model"]
    voice = book.audio_preferences["voice"]
    chapter_ids = Enum.map(chapters, & &1.id)

    # Load existing state
    audios = list_chapter_audio_for_chapters(chapter_ids)
    tasks = list_tasks_for_chapters(chapter_ids)

    # Index by chapter_id for fast lookup
    audio_by_chapter = Map.new(audios, &{&1.chapter_id, &1})
    pending_chapter_ids =
      tasks
      |> Enum.filter(&(&1.status in ["pending", "processing"]))
      |> Enum.map(& &1.chapter_id)
      |> MapSet.new()

    # Most recent failed task per chapter matching current profile
    failed_by_chapter =
      tasks
      |> Enum.filter(&(&1.status == "failed" && &1.model == model && &1.voice == voice))
      |> Enum.group_by(& &1.chapter_id)
      |> Enum.map(fn {ch_id, ch_tasks} ->
        most_recent = Enum.max_by(ch_tasks, & &1.updated_at, NaiveDateTime)
        {ch_id, most_recent}
      end)
      |> Map.new()

    # Determine which chapters need generation
    to_generate =
      Enum.filter(chapters, fn ch ->
        audio = Map.get(audio_by_chapter, ch.id)
        has_pending = MapSet.member?(pending_chapter_ids, ch.id)
        failed_task = Map.get(failed_by_chapter, ch.id)

        needs_audio = audio == nil || audio.model != model || audio.voice != voice
        not_in_flight = !has_pending
        not_exhausted = failed_task == nil || failed_task.attempt_number < @max_attempts

        needs_audio && not_in_flight && not_exhausted
      end)

    # Queue generation for each
    for ch <- to_generate do
      failed_task = Map.get(failed_by_chapter, ch.id)
      attempt = if failed_task, do: failed_task.attempt_number + 1, else: 1
      generate_for_chapter(book.id, ch.id, model: model, voice: voice, attempt_number: attempt)
    end

    {:ok, length(to_generate)}
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/noah/projects/readaloud && mix test apps/readaloud_audiobook/test/readaloud_audiobook_test.exs`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/readaloud_audiobook/lib/readaloud_audiobook.ex apps/readaloud_audiobook/test/readaloud_audiobook_test.exs
git commit -m "feat: implement ensure_audio_generated/2 with idempotent auto-queuing"
```

---

### Task 7: Remove `generate_for_book/2`

**Files:**
- Modify: `apps/readaloud_audiobook/lib/readaloud_audiobook.ex`
- Modify: `apps/readaloud_audiobook/test/readaloud_audiobook_test.exs`

- [ ] **Step 1: Remove the `generate_for_book/2` test**

Delete the `describe "generate_for_book/1"` block (lines 28-34) from `apps/readaloud_audiobook/test/readaloud_audiobook_test.exs`.

- [ ] **Step 2: Remove the `generate_for_book/2` function**

Delete the function (lines 26-36) from `apps/readaloud_audiobook/lib/readaloud_audiobook.ex`.

- [ ] **Step 3: Check for remaining references**

Run: `cd /home/noah/projects/readaloud && grep -r "generate_for_book" --include="*.ex" --include="*.exs" apps/`
Expected: No matches (function is not called from BookLive or anywhere else).

- [ ] **Step 4: Run all tests**

Run: `cd /home/noah/projects/readaloud && mix test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add apps/readaloud_audiobook/lib/readaloud_audiobook.ex apps/readaloud_audiobook/test/readaloud_audiobook_test.exs
git commit -m "refactor: remove generate_for_book/2, replaced by ensure_audio_generated/2"
```

---

## Chunk 2: BookLive Overhaul

### Task 8: Update `build_audio_map/2` with profile-aware states

**Files:**
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex`

- [ ] **Step 1: Replace `build_audio_map/1` with `build_audio_map/2`**

In `apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex`, replace the entire `build_audio_map/1` function (lines 279-302) with:

```elixir
  defp build_audio_map(chapters, book) do
    chapter_ids = Enum.map(chapters, & &1.id)
    audios = ReadaloudAudiobook.list_chapter_audio_for_chapters(chapter_ids)
    tasks = ReadaloudAudiobook.list_tasks_for_chapters(chapter_ids)

    model = get_in(book.audio_preferences || %{}, ["model"])
    voice = get_in(book.audio_preferences || %{}, ["voice"])

    audio_by_chapter = Map.new(audios, &{&1.chapter_id, &1})

    # Active tasks indexed by chapter
    active_by_chapter =
      tasks
      |> Enum.filter(&(&1.status in ["pending", "processing"]))
      |> Map.new(&{&1.chapter_id, &1})

    # Most recent failed task per chapter matching current profile
    failed_by_chapter =
      tasks
      |> Enum.filter(&(&1.status == "failed" && &1.model == model && &1.voice == voice))
      |> Enum.group_by(& &1.chapter_id)
      |> Enum.map(fn {ch_id, ch_tasks} ->
        {ch_id, Enum.max_by(ch_tasks, & &1.updated_at, NaiveDateTime)}
      end)
      |> Map.new()

    Map.new(chapter_ids, fn id ->
      audio = Map.get(audio_by_chapter, id)
      active_task = Map.get(active_by_chapter, id)
      failed_task = Map.get(failed_by_chapter, id)
      audio_matches = audio != nil && audio.model == model && audio.voice == voice

      cond do
        # Priority 1: Active task exists
        active_task != nil && active_task.status == "processing" && audio != nil && !audio_matches ->
          {id, {:generating, audio.duration_seconds}}

        active_task != nil && active_task.status == "pending" && audio != nil && !audio_matches ->
          {id, {:queued, audio.duration_seconds}}

        active_task != nil && active_task.status == "processing" ->
          {id, :processing}

        active_task != nil && active_task.status == "pending" ->
          {id, :queued}

        # Priority 2: Audio matches profile
        audio_matches ->
          {id, {:ready, audio.duration_seconds}}

        # Priority 3: Stale audio, no active task
        audio != nil && !audio_matches ->
          {id, {:stale, audio.duration_seconds}}

        # Priority 4-5: Failed tasks (matching profile only)
        failed_task != nil && failed_task.attempt_number >= 3 ->
          {id, :skipped}

        failed_task != nil ->
          {id, :failed}

        # Priority 6: Nothing
        true ->
          {id, nil}
      end
    end)
  end
```

- [ ] **Step 2: Update all `build_audio_map` call sites in BookLive**

There are three call sites to update:

1. In `mount/3` (line 11): change `build_audio_map(chapters)` to `build_audio_map(chapters, book)`
2. In `handle_event("generate_batch", ...)` (line 56): change `build_audio_map(chapters)` to `build_audio_map(chapters, book)` — this handler will be removed in Task 10, but update it now so the module compiles.
3. In `handle_info({:task_updated, ...})` (line 132): change `build_audio_map(chapters)` to `build_audio_map(chapters, socket.assigns.book)`

- [ ] **Step 3: Verify compilation**

Run: `cd /home/noah/projects/readaloud && mix compile --warnings-as-errors`
Expected: Compiles with no errors.

- [ ] **Step 4: Commit**

```bash
git add apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex
git commit -m "feat: profile-aware build_audio_map/2 with composite states"
```

---

### Task 9: Update `audio_duration/2` and `audio_count/1` helpers

**Files:**
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex`

- [ ] **Step 1: Update `audio_duration/2` to handle all duration-carrying states**

Replace the `audio_duration/2` function (lines 336-346) with:

```elixir
  defp audio_duration(audio_map, chapter_id) do
    case Map.get(audio_map, chapter_id) do
      {state, seconds} when state in [:ready, :stale, :generating, :queued] and is_number(seconds) and seconds > 0 ->
        mins = trunc(seconds / 60)
        secs = trunc(rem(trunc(seconds), 60))
        "#{mins}:#{String.pad_leading("#{secs}", 2, "0")}"

      _ ->
        nil
    end
  end
```

- [ ] **Step 2: Verify compilation and tests**

Run: `cd /home/noah/projects/readaloud && mix compile --warnings-as-errors && mix test`
Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex
git commit -m "feat: audio_duration handles all duration-carrying states"
```

---

### Task 10: Overhaul BookLive mount, event handlers, and PubSub

**Files:**
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex`

- [ ] **Step 1: Update `mount/3`**

Replace the mount function (lines 7-34) with:

```elixir
  @impl true
  def mount(%{"id" => id}, _session, socket) do
    book = ReadaloudLibrary.get_book!(String.to_integer(id))
    chapters = ReadaloudLibrary.list_chapters(book.id)
    progress = ReadaloudReader.get_progress(book.id)
    audio_map = build_audio_map(chapters, book)
    models = fetch_models()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ReadaloudWeb.PubSub, "tasks:audiobook:#{book.id}")
      ReadaloudAudiobook.ensure_audio_generated(book, chapters)
    end

    {:ok,
     socket
     |> assign(
       active_nav: :library,
       task_count: active_task_count(),
       book: book,
       chapters: chapters,
       progress: progress,
       audio_map: audio_map,
       models: models,
       selected_model: default_model(book, models),
       selected_voice: default_voice(book, models),
       page_title: book.title
     )}
  end
```

- [ ] **Step 2: Remove old event handlers, add new ones**

Delete these handlers:
- `handle_event("generate_batch", ...)` (lines 37-58)
- `handle_event("select_all_chapters", ...)` (lines 61-64)
- `handle_event("select_from_current", ...)` (lines 67-77)
- `handle_event("toggle_chapter", ...)` (lines 80-90)
- `handle_event("retry_chapter_audio", ...)` (lines 99-105)
- `handle_event("toggle_generate_panel", ...)` (lines 113-115)

Keep the existing `select_model` and `select_voice` handlers — they are used by the "Set up audio" popover.

Add these new handlers (after the `delete_book` handler):

```elixir
  @impl true
  def handle_event("activate_audio", _params, socket) do
    book = socket.assigns.book
    model = socket.assigns.selected_model
    voice = socket.assigns.selected_voice

    {:ok, book} = ReadaloudLibrary.update_book(book, %{
      audio_preferences: %{"model" => model, "voice" => voice}
    })

    chapters = socket.assigns.chapters
    ReadaloudAudiobook.ensure_audio_generated(book, chapters)

    {:noreply,
     socket
     |> assign(
       book: book,
       audio_map: build_audio_map(chapters, book)
     )}
  end

  @impl true
  def handle_event("update_audio_settings", %{"model" => model, "voice" => voice}, socket) do
    book = socket.assigns.book

    {:ok, book} = ReadaloudLibrary.update_book(book, %{
      audio_preferences: %{"model" => model, "voice" => voice}
    })

    chapters = socket.assigns.chapters
    ReadaloudAudiobook.ensure_audio_generated(book, chapters)

    {:noreply,
     socket
     |> assign(
       book: book,
       selected_model: model,
       selected_voice: voice,
       audio_map: build_audio_map(chapters, book)
     )}
  end

```

- [ ] **Step 3: Update PubSub handler**

Replace the `handle_info({:task_updated, ...})` handler with:

```elixir
  @impl true
  def handle_info({:task_updated, task}, socket) do
    book = socket.assigns.book
    chapters = socket.assigns.chapters

    if task.status == "completed" do
      ReadaloudAudiobook.ensure_audio_generated(book, chapters)
    end

    {:noreply, assign(socket, audio_map: build_audio_map(chapters, book))}
  end
```

- [ ] **Step 4: Verify no dead helpers**

Keep `current_chapter_number/2` — it is still called by `progress_count/2`.
Keep `is_current?/2`, `resume_path/2`, `progress_count/2` — they're still used in the template.

- [ ] **Step 5: Verify compilation**

Run: `cd /home/noah/projects/readaloud && mix compile --warnings-as-errors`
Expected: Compiles. There may be warnings about unused `current_chapter_number` if it wasn't deleted, or about the template still referencing old assigns — that's fine, we fix the template next.

- [ ] **Step 6: Commit**

```bash
git add apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex
git commit -m "feat: overhaul BookLive mount, handlers, PubSub for auto-generation"
```

---

### Task 11: Rewrite BookLive template

**Files:**
- Modify: `apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex`

- [ ] **Step 1: Replace the entire `render/1` function**

Replace the render function (lines 136-275) with:

```elixir
  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Back link --%>
      <.link navigate={~p"/"} class="flex items-center gap-1 text-sm text-base-content/60 hover:text-base-content mb-6">
        <.icon name="hero-arrow-left-mini" class="w-4 h-4" /> Back to Library
      </.link>

      <%!-- Book header --%>
      <div class="flex flex-col sm:flex-row gap-6 mb-8">
        <img :if={cover_url(@book)} src={"/api/books/#{@book.id}/cover"} class="w-24 rounded-lg shadow" />
        <div
          :if={!cover_url(@book)}
          class="w-24 h-32 rounded-lg"
          style={gradient_style(@book)}
        />
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <h1 class="text-2xl font-bold tracking-tight"><%= @book.title %></h1>
            <%= if @book.audio_preferences do %>
              <div class="dropdown dropdown-end">
                <div tabindex="0" role="button" class="btn btn-ghost btn-sm btn-square">
                  <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
                </div>
                <div tabindex="0" class="dropdown-content z-10 card card-compact bg-base-200 shadow-xl w-64 p-4">
                  <form phx-submit="update_audio_settings">
                    <div class="form-control mb-3">
                      <label class="label label-text text-xs uppercase">Model</label>
                      <select name="model" class="select select-sm select-bordered w-full">
                        <option
                          :for={m <- @models}
                          value={m[:id]}
                          selected={m[:id] == @selected_model}
                        >
                          <%= m[:id] %>
                        </option>
                      </select>
                    </div>
                    <div class="form-control mb-3">
                      <label class="label label-text text-xs uppercase">Voice</label>
                      <select name="voice" class="select select-sm select-bordered w-full">
                        <% current_model = Enum.find(@models, &(&1[:id] == @selected_model)) %>
                        <option
                          :for={v <- (current_model && current_model[:voices]) || []}
                          value={v}
                          selected={v == @selected_voice}
                        >
                          <%= v %>
                        </option>
                      </select>
                    </div>
                    <p class="text-xs text-base-content/50 text-center mb-2">
                      <%= audio_count(@audio_map) %>/<%= length(@chapters) %> chapters ready
                    </p>
                    <button type="submit" class="btn btn-primary btn-sm w-full">Save</button>
                  </form>
                </div>
              </div>
            <% end %>
          </div>
          <p :if={@book.author} class="text-base-content/60 mt-1"><%= @book.author %></p>
          <div class="flex flex-wrap gap-2 mt-3">
            <span class="badge badge-outline"><%= length(@chapters) %> chapters</span>
            <span class="badge badge-outline">
              <%= progress_count(@progress, @book) %>/<%= length(@chapters) %> read
            </span>
            <%= if @book.audio_preferences do %>
              <span class="badge badge-outline">
                <%= audio_count(@audio_map) %>/<%= length(@chapters) %> audio
              </span>
            <% end %>
          </div>
          <%= if @book.audio_preferences do %>
            <p class="text-xs text-base-content/50 mt-2">
              <%= audio_count(@audio_map) %>/<%= length(@chapters) %> chapters ready · <%= @book.audio_preferences["model"] %> / <%= @book.audio_preferences["voice"] %>
            </p>
          <% end %>
          <div class="flex flex-wrap gap-2 mt-4">
            <.link navigate={resume_path(@book, @progress)} class="btn btn-primary btn-sm">
              Continue Reading
            </.link>
            <%= if !@book.audio_preferences do %>
              <div class="dropdown dropdown-end">
                <div tabindex="0" role="button" class="btn btn-sm btn-outline">
                  Set up audio
                </div>
                <div tabindex="0" class="dropdown-content z-10 card card-compact bg-base-200 shadow-xl w-64 p-4">
                  <div class="form-control mb-3">
                    <label class="label label-text text-xs uppercase">Model</label>
                    <select phx-change="select_model" name="model" class="select select-sm select-bordered w-full">
                      <option
                        :for={m <- @models}
                        value={m[:id]}
                        selected={m[:id] == @selected_model}
                      >
                        <%= m[:id] %>
                      </option>
                    </select>
                  </div>
                  <div class="form-control mb-3">
                    <label class="label label-text text-xs uppercase">Voice</label>
                    <select phx-change="select_voice" name="voice" class="select select-sm select-bordered w-full">
                      <% current_model = Enum.find(@models, &(&1[:id] == @selected_model)) %>
                      <option
                        :for={v <- (current_model && current_model[:voices]) || []}
                        value={v}
                        selected={v == @selected_voice}
                      >
                        <%= v %>
                      </option>
                    </select>
                  </div>
                  <button phx-click="activate_audio" class="btn btn-primary btn-sm w-full">
                    Activate
                  </button>
                </div>
              </div>
            <% end %>
            <button
              phx-click="delete_book"
              data-confirm="This will remove the book and all generated audio. Continue?"
              class="btn btn-sm btn-ghost text-error"
            >
              Delete Book
            </button>
          </div>
        </div>
      </div>

      <%!-- Chapter list --%>
      <div class="space-y-1">
        <div
          :for={ch <- @chapters}
          class={[
            "flex items-center gap-3 p-3 rounded-lg",
            is_current?(ch, @progress) && "bg-primary/10"
          ]}
        >
          <span class="text-sm font-mono text-base-content/40 w-8"><%= ch.number %></span>
          <.link
            navigate={~p"/books/#{@book.id}/read/#{ch.id}"}
            class="flex-1 text-sm hover:text-primary"
          >
            <%= ch.title || "Chapter #{ch.number}" %>
          </.link>
          <%= case Map.get(@audio_map, ch.id) do %>
            <% {:ready, _} -> %>
              <span class="text-xs text-base-content/40"><%= audio_duration(@audio_map, ch.id) %></span>
            <% {:stale, _} -> %>
              <span class="text-xs text-base-content/40"><%= audio_duration(@audio_map, ch.id) %></span>
            <% {:generating, _} -> %>
              <span class="text-xs text-base-content/40 animate-pulse"><%= audio_duration(@audio_map, ch.id) %></span>
            <% {:queued, _} -> %>
              <span class="text-xs text-base-content/40"><%= audio_duration(@audio_map, ch.id) %></span>
            <% :processing -> %>
              <span class="text-xs text-base-content/40 animate-pulse">generating...</span>
            <% :queued -> %>
              <span class="text-xs text-base-content/40">queued</span>
            <% :failed -> %>
              <span class="text-xs text-error">failed</span>
            <% :skipped -> %>
              <span class="text-xs text-error">skipped</span>
            <% _ -> %>
          <% end %>
          <span :if={is_current?(ch, @progress)} class="badge badge-primary badge-xs">
            CURRENT
          </span>
        </div>
      </div>
    </div>
    """
  end
```

- [ ] **Step 2: Verify compilation**

Run: `cd /home/noah/projects/readaloud && mix compile --warnings-as-errors`
Expected: Compiles with no errors. Check for unused variable warnings and fix if needed.

- [ ] **Step 3: Manual smoke test**

Run: `cd /home/noah/projects/readaloud && mix phx.server`

Verify in browser:
- Book with no `audio_preferences`: "Set up audio" button shows, no audio status in chapter list
- Click "Set up audio" → popover with model/voice dropdowns → click "Activate" → chapters start showing "queued"/"generating..."
- Book with `audio_preferences`: gear icon visible, summary line shows, chapter durations display

- [ ] **Step 4: Commit**

```bash
git add apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex
git commit -m "feat: rewrite BookLive template with auto-generation UI"
```

---

### Task 12: Run full test suite and verify

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `cd /home/noah/projects/readaloud && mix test`
Expected: All tests pass.

- [ ] **Step 2: Check for compiler warnings**

Run: `cd /home/noah/projects/readaloud && mix compile --warnings-as-errors`
Expected: No warnings.

- [ ] **Step 3: Final commit if any cleanup was needed**

Only if fixes were required from steps 1-2.
