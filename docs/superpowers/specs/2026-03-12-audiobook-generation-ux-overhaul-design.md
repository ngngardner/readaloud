# Audiobook Generation UX Overhaul

## Summary

Replace the manual batch-select-and-generate workflow in BookLive with an automatic, profile-driven system. Users activate audio for a book by confirming a model/voice profile; from that point, all missing or stale chapters are automatically queued for generation. The chapter list shows simple text status indicators. Failed chapters are auto-retried up to a threshold, then permanently skipped with no manual retry UI.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Auto-generation trigger | Explicit opt-in (activate per book) | Avoids surprise resource usage; `audio_preferences == nil` is the "not activated" signal |
| Stale audio handling | Keep existing audio, regenerate as missing | Changing voice marks old audio stale; it stays playable until replaced |
| Batch sizing | Queue all missing at once | Simple; Oban serializes via concurrency-1 queue |
| Settings UI | Gear icon popover (DaisyUI dropdown) | Compact; settings are rarely changed after activation |
| Failure handling | Auto-retry up to 3 task cycles (9 total attempts), then skip | No manual retry UI; user investigates outside the app if needed |
| Auto-generation location | `ReadaloudAudiobook.ensure_audio_generated/2` | Domain logic in domain module; LiveView just calls it on mount |

## Schema Changes

### Migration: Add `model` and `voice` to `chapter_audios`

```elixir
alter table(:chapter_audios) do
  add :model, :string
  add :voice, :string
end
```

Records which profile generated the audio. Used by `build_audio_map` to detect staleness: if `chapter_audio.model != book.audio_preferences["model"]` or `chapter_audio.voice != book.audio_preferences["voice"]`, the audio is stale.

### Migration: Add `attempt_number` to `audiobook_tasks`

```elixir
alter table(:audiobook_tasks) do
  add :attempt_number, :integer, default: 1
end
```

Tracks how many times a task has been created for a given chapter under a specific profile. Each task gets Oban's 3 internal retries. After 3 task creations (attempt_number >= 3), the chapter is skipped. Resets on model/voice change because the failed-task query in `ensure_audio_generated` filters by current model/voice — old profile failures don't count against the new profile.

## New Function: `ReadaloudAudiobook.ensure_audio_generated/2`

```elixir
@doc """
Ensures all chapters for a book have audio matching the current profile.
Idempotent — safe to call on every mount or task completion.
Returns {:ok, queued_count}.
"""
def ensure_audio_generated(book, chapters)
```

**Logic:**
1. Return `{:ok, 0}` if `book.audio_preferences` is `nil` (not activated)
2. Extract `{model, voice}` from `book.audio_preferences` using string keys (`book.audio_preferences["model"]`, `book.audio_preferences["voice"]`)
3. Load all `ChapterAudio` records for these chapter IDs
4. Load all `AudiobookTask` records with status `"pending"` or `"processing"` for these chapter IDs
5. Load most recent `"failed"` task per chapter **where task model/voice matches current profile** (for `attempt_number` check — this ensures changing voice resets the failure counter)
6. For each chapter, determine if it needs generation:
   - No `ChapterAudio` exists, OR `ChapterAudio` model/voice doesn't match current profile
   - AND no pending/processing task exists for this chapter
   - AND most recent failed task's `attempt_number < 3` (or no failed task exists)
7. Call `generate_for_chapter/3` for each, passing `attempt_number` in opts (previous failed `attempt_number + 1`, or `1` if no prior failure)
8. Return `{:ok, length(queued)}`

## Modified Function: `generate_for_chapter/3`

Accept `attempt_number` in opts (default 1). Pass through to `AudiobookTask` changeset. The `AudiobookTask.changeset/2` cast list must be updated to include `:attempt_number`.

## Modified Worker: `GenerateJob`

When saving `ChapterAudio` on completion, persist `model` and `voice` from the `AudiobookTask` record into the `ChapterAudio` insert. These fields are already available on the task. The `ChapterAudio.changeset/2` cast list must be updated to include `:model` and `:voice`.

## Updated `build_audio_map/2`

Signature changes from `build_audio_map(chapters)` to `build_audio_map(chapters, book)`.

**Return values per chapter:**

| Value | Meaning |
|---|---|
| `{:ready, duration}` | Audio exists, matches current profile |
| `{:stale, duration}` | Audio exists, model/voice doesn't match, no task in flight |
| `{:generating, duration}` | Audio exists (stale), task with status `"processing"` — audio still playable |
| `{:queued, duration}` | Audio exists (stale), task with status `"pending"` — audio still playable |
| `:processing` | No audio, task with status `"processing"` |
| `:queued` | No audio, task with status `"pending"` |
| `:failed` | Task failed, under retry threshold |
| `:skipped` | Task failed, at or above retry threshold (permanently failed) |
| `nil` | No audio, no task |

**Priority order** (chapter may have both audio and a task):
1. Pending/processing task exists:
   - If stale audio also exists → `{:generating, duration}` or `{:queued, duration}` (preserves playable duration)
   - If no audio → `:processing` or `:queued`
2. Audio matches profile → `{:ready, duration}`
3. Audio doesn't match, no task → `{:stale, duration}`
4. Failed task (matching current profile) with `attempt_number >= 3` → `:skipped`
5. Failed task (matching current profile) with `attempt_number < 3` → `:failed`
6. Otherwise → `nil`

**Failed-task profile filtering:** `list_tasks_for_chapters/1` returns full `AudiobookTask` structs (including `model` and `voice` fields). The profile matching for `:failed`/`:skipped` determination is done in Elixir-level map-building logic by comparing `task.model == book.audio_preferences["model"]` and `task.voice == book.audio_preferences["voice"]`. Failed tasks from other profiles are ignored.

## BookLive Changes

### Mount

1. Load book, chapters, reading progress (unchanged)
2. Call `build_audio_map(chapters, book)` (updated signature)
3. Fetch models, set default model/voice (unchanged)
4. Subscribe to PubSub (unchanged)
5. If `connected?(socket)`, call `ReadaloudAudiobook.ensure_audio_generated(book, chapters)`

### PubSub Handler

On `{:task_updated, task}`:
1. If task status is `"completed"`, call `ensure_audio_generated(book, chapters)` (idempotent; may queue stale chapters)
2. Rebuild `audio_map` **after** `ensure_audio_generated` completes, so newly queued tasks are reflected in the map

### Removed Event Handlers

- `"generate_batch"` — no batch selection
- `"select_all_chapters"` — no checkboxes
- `"select_from_current"` — no checkboxes
- `"toggle_chapter"` — no checkboxes
- `"retry_chapter_audio"` — no retry button
- `"toggle_generate_panel"` — no panel toggle

### New Event Handlers

- `"activate_audio"` — calls `ReadaloudLibrary.update_book/2` to save model/voice to `audio_preferences`, re-assigns the updated book struct to the socket, calls `ensure_audio_generated`, rebuilds `audio_map`
- `"update_audio_settings"` — same flow as `"activate_audio"`: update book, re-assign, ensure generation, rebuild map

### Removed Assigns

- `selected_chapters`
- `show_generate_panel`

## UI Design

### Book Header — Not Activated (`audio_preferences == nil`)

"Set up audio" button in book metadata area. Clicking opens popover with model/voice dropdowns pre-filled with app defaults and an "Activate" button.

### Book Header — Activated

Gear icon next to book title. Clicking opens DaisyUI `dropdown` with:
- Model select
- Voice select
- Status summary: "N/M chapters ready"

Changing model/voice saves immediately and triggers `ensure_audio_generated`.

Below the book metadata, a summary line: "5/9 chapters ready · kokoro / af_heart". "Ready" means audio matches the current profile (only counts `:ready` state, not stale/generating/queued). This serves as a progress indicator for the current profile.

### Chapter List Rows

Each row contains:
- Chapter number + title (clickable link to reader)
- Right-aligned status text
- "CURRENT" badge for reading position

Status text rendering:

| State | Text | Style |
|---|---|---|
| `{:ready, dur}` | Formatted duration (e.g., "12:34") | Muted text |
| `{:stale, dur}` | Formatted duration | Muted text (still playable) |
| `{:generating, dur}` | Formatted duration | Muted text + `animate-pulse` (playable, regenerating) |
| `{:queued, dur}` | Formatted duration | Muted text (playable, queued for regeneration) |
| `:processing` | "generating..." | `animate-pulse` |
| `:queued` | "queued" | Muted text |
| `:failed` | "failed" | Red/error text |
| `:skipped` | "skipped" | Red/error text |
| `nil` | (nothing) | — |

No icons, checkboxes, or retry buttons.

## Edge Cases

### LocalAI Down

Jobs fail during synthesis. Oban retries 3x with backoff. After 3 Oban attempts, task status becomes `"failed"`. On next `ensure_audio_generated` call, a new task is created with incremented `attempt_number`. After 3 task cycles (9 total real attempts), chapter is skipped.

### Large Books (200+ chapters)

All chapters queue at once. Oban jobs are SQLite rows, not in-memory. `build_audio_map` runs two indexed queries. PubSub updates the UI per completion. No memory or performance concern.

### Model/Voice Changed Mid-Generation

Pending/processing tasks with old voice complete and save `ChapterAudio` with old model/voice. On their completion PubSub, `ensure_audio_generated` detects staleness and re-queues. At most one chapter of "wasted" work (TTS concurrency 1).

### Reader View Compatibility

`ReaderLive` doesn't know about profiles. It plays whatever `ChapterAudio` exists. If stale audio exists while a new task is processing, the stale audio remains playable. No changes needed to `ReaderLive`.

### Double Mount / Reconnect

`ensure_audio_generated` is idempotent. Existing pending tasks prevent duplicate creation.

### Speed Not Tracked in Profiles

`audio_preferences` stores only `model` and `voice`. Speed (`AudiobookTask.speed`) uses the default (1.0) and is not part of the staleness check. Speed changes are not a current requirement.

### Task Accumulation

Auto-retry creates up to 3 failed task rows per chapter per profile. For a single-user app with typical book sizes, this accumulation is negligible. The existing `clear_completed_tasks/0` (used by TasksLive) handles cleanup. No additional cleanup logic needed.

## Files to Modify

1. `apps/readaloud_audiobook/lib/readaloud_audiobook/audiobook_task.ex` — add `attempt_number` field
2. `apps/readaloud_audiobook/lib/readaloud_audiobook/chapter_audio.ex` — add `model`, `voice` fields
3. `apps/readaloud_audiobook/lib/readaloud_audiobook.ex` — add `ensure_audio_generated/2`, modify `generate_for_chapter/3`
4. `apps/readaloud_audiobook/lib/readaloud_audiobook/generate_job.ex` — persist model/voice to ChapterAudio on completion
5. `apps/readaloud_web/lib/readaloud_web_web/live/book_live.ex` — new mount flow, new event handlers, new template, updated `build_audio_map/2`, updated `audio_duration/2` helper to pattern-match all duration-carrying states (`{:ready, _}`, `{:stale, _}`, `{:generating, _}`, `{:queued, _}`)
6. `apps/readaloud_audiobook/lib/readaloud_audiobook.ex` — remove `generate_for_book/2` (replaced by `ensure_audio_generated/2`)
7. New migration file for schema changes
