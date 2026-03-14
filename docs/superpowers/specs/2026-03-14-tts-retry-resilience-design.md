# TTS Retry Resilience Design

**Date:** 2026-03-14
**Status:** Draft
**Scope:** `readaloud_tts`, `readaloud_audiobook`

## Problem

The audiobook generation pipeline fails permanently on transient LocalAI connection errors. When other agents load new models into LocalAI (causing Kokoro TTS to be evicted/reloaded), active TTS requests fail with `:closed`, `:econnrefused`, or `:timeout` errors. The pipeline has no retry mechanism, so a single blip kills an entire chapter's synthesis — even if 80+ chunks already completed successfully.

Additionally, failed Oban jobs can leave tasks stuck in `processing` state permanently (zombie tasks) when exceptions bypass the error handler, making them invisible to the retry system.

### Failure Modes Observed

| Error | Cause | Recovery Time |
|-------|-------|---------------|
| `Req.TransportError: closed` | LocalAI closed connection during model swap | 5-30s |
| `Req.TransportError: econnrefused` | LocalAI backend process restarting | 10-60s |
| `Req.TransportError: timeout` | LocalAI busy loading model, can't serve request | 15-60s |

### Affected Data (Current)

- Task 64 (ch1): `processing`, timeout on chunk 9/10
- Task 65 (ch2): `processing`, closed on chunk 1/103
- Task 69 (ch6): `processing`, econnrefused on chunk 9/111
- Task 74 (ch4): `processing`, closed on chunk 13/36 (attempt 2)

## Design

### Approach: Req-level retry with extended backoff

Add retry handling at the HTTP client level. Req's built-in `:transient` retry mode handles exactly the transport errors we're seeing. Extend the backoff ceiling to bridge model reload times (up to 60s).

**No per-chunk checkpointing.** Restarting a chapter from scratch is acceptable — the longest chapter takes ~10 minutes, and the instability is temporary (active model development). Simplicity wins.

### Change 1: Req retry in `local_ai_provider.ex`

Add to both `synthesize/2` and `transcribe/2` Req.post calls:

```elixir
retry: :transient,
retry_delay: fn attempt -> min(1_000 * Integer.pow(2, attempt), 30_000) end,
max_retries: 8
```

Backoff schedule (Req's `retry_count` is 0-based): 1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s = ~2 minutes total retry window. This bridges even the longest model reload scenarios.

`:transient` retries on transport errors (connection refused, reset, timeout) AND server error statuses (408, 429, 500, 502, 503, 504) — but not client errors (400/401/404). This is ideal: LocalAI may return 500/502/503 during model loading, and those should be retried too.

**Intentionally excluded:** `list_voices/0` and `list_models_and_voices/1` — these are UI-triggered, not pipeline-critical. A transient error on a model list call is a momentary UI glitch, not data loss.

### Change 2: Exception safety in `generate_job.ex`

Wrap the `perform/1` body in a try/rescue to catch any uncaught exceptions and transition the task to `failed` state:

The entire `perform/1` function body (including `Repo.get!`) is wrapped in an implicit `try/rescue`. The rescue block does a **fresh `Repo.get`** (not `get!`) using `task_id` from the function head pattern match — this is always bound regardless of where the exception occurs. The outer `task` variable is intentionally NOT used in the rescue since it may not be bound or may have been rebound.

```elixir
def perform(%Oban.Job{args: %{"task_id" => task_id}} = job) do
  task = Repo.get!(AudiobookTask, task_id)
  # ... existing crash recovery + processing logic ...
rescue
  exception ->
    # Fresh lookup — task_id is bound from function head, always safe
    if failed_task = Repo.get(AudiobookTask, task_id) do
      update_task(failed_task, %{
        status: "failed",
        error_message: "Unexpected error: #{Exception.message(exception)}"
      })
    end
    reraise exception, __STACKTRACE__
end
```

This ensures tasks always transition to `failed` on error, even if the exception happens outside the `with` block. The `reraise` preserves Oban's retry logic — Oban will catch the re-raised exception and schedule the next attempt if retries remain.

### Change 3: Fix zombie tasks in production

One-time database fix to transition stuck tasks from `processing` to `failed`. All four zombie tasks need fixing — their corresponding Oban jobs are either `discarded` (gave up) or `completed` (succeeded from Oban's perspective but the task record was never updated):

| Task | Oban Job | Oban State | Task State | Action |
|------|----------|------------|------------|--------|
| 64 | - | - | processing | → failed |
| 65 | 67 | discarded | processing | → failed |
| 69 | 71 | discarded | processing | → failed |
| 74 | 76 | completed | processing | → failed |

Additionally, Oban job 69 (task 67 ch4) is `retryable` at attempt 15/17 but the task record is already `failed` from a previous attempt. This job should be cancelled to prevent it from running stale work after deployment.

```sql
UPDATE audiobook_tasks
SET status = 'failed'
WHERE status = 'processing'
  AND id IN (64, 65, 69, 74);

-- Cancel stale Oban job that would run against already-failed task
UPDATE oban_jobs
SET state = 'cancelled'
WHERE id = 69
  AND state = 'retryable';
```

## What This Does NOT Change

- **Chunk processing flow**: `Enum.reduce_while` stays as-is. A chapter restarts from chunk 1 on retry.
- **Oban retry strategy**: Still `max_attempts: 3` with crash recovery bump. The Req retries handle transient blips; Oban retries handle sustained outages.
- **`@max_attempts` in `readaloud_audiobook.ex`**: Still 3 total attempts per task.
- **TextChunker, WAV handling, TimingAligner**: Untouched.
- **`list_voices/0`, `list_models_and_voices/1`**: No retry added — UI-triggered, not pipeline-critical.

## Testing

- Verify `mix compile` succeeds
- Verify existing tests pass (`mix test`)
- Deploy to pylon, confirm service starts
- Retry a failed chapter and observe retry log output
