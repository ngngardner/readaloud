// Client-side durable buffer for reading-progress observations.
//
// The reader's persistence boundary used to be LiveView-only: every
// `audio_position` push went straight to the WS, with no fallback if the
// socket was suspended. On mobile, locking the screen suspends the WS but
// not the native audio session — so audio kept advancing while every
// position observation was silently dropped, and PC resume landed at a
// stale chapter.
//
// This module fixes that by giving every observation two delivery paths:
//   1. `pushEvent` over the WS (immediate, optimistic)
//   2. `navigator.sendBeacon` to /api/books/:id/progress
//      (fired on visibilitychange:hidden + pagehide)
//
// Both transports converge on `ReadaloudReader.observe!/1`, which is
// idempotent under replay (stale-drop by `observed_at`). So sending the
// same observation twice is harmless. The buffer's job is to make sure
// every observation hits *at least one* of the two paths.
//
// Storage: a small bounded queue in localStorage keyed by bookId. Entries
// older than 60s are pruned on every observe — they're either already
// delivered (WS happy path) or no longer worth resending (server has
// fresher state from in-flight ticks).

import { type JsonValue, isJsonObject, parseJson } from "./types";

export interface ProgressObservation {
  readonly chapter_id: string;
  readonly audio_position_ms?: number;
  readonly scroll_position?: number;
  readonly observed_at: string;
}

export interface ProgressBuffer {
  observe(obs: Omit<ProgressObservation, "observed_at">): void;
  detach(): void;
}

interface ProgressBufferDeps {
  readonly bookId: number;
  readonly beaconUrl: string;
  readonly pushObservations: (
    observations: ReadonlyArray<ProgressObservation>,
  ) => void;
}

const STORAGE_KEY_PREFIX = "readaloud-progress-buffer:";
const MAX_BUFFER_ENTRIES = 50;
const BACKLOG_PRUNE_AGE_MS = 60_000;

function storageKey(bookId: number): string {
  return `${STORAGE_KEY_PREFIX}${bookId}`;
}

function parseObservation(v: JsonValue): ProgressObservation | null {
  if (!isJsonObject(v)) return null;
  if (typeof v.chapter_id !== "string") return null;
  if (typeof v.observed_at !== "string") return null;
  const out: {
    -readonly [K in keyof ProgressObservation]: ProgressObservation[K];
  } = {
    chapter_id: v.chapter_id,
    observed_at: v.observed_at,
  };
  if (typeof v.audio_position_ms === "number") {
    out.audio_position_ms = v.audio_position_ms;
  }
  if (typeof v.scroll_position === "number") {
    out.scroll_position = v.scroll_position;
  }
  return out;
}

function readBacklog(bookId: number): ReadonlyArray<ProgressObservation> {
  const raw = localStorage.getItem(storageKey(bookId));
  if (!raw) return [];
  try {
    const json = parseJson(raw);
    if (!Array.isArray(json)) return [];
    const out: ProgressObservation[] = [];
    for (const entry of json) {
      const obs = parseObservation(entry);
      if (obs) out.push(obs);
    }
    return out;
  } catch {
    return [];
  }
}

function writeBacklog(
  bookId: number,
  backlog: ReadonlyArray<ProgressObservation>,
): void {
  if (backlog.length === 0) {
    localStorage.removeItem(storageKey(bookId));
    return;
  }
  localStorage.setItem(storageKey(bookId), JSON.stringify(backlog));
}

function pruneBacklog(
  backlog: ReadonlyArray<ProgressObservation>,
  now: number,
): ReadonlyArray<ProgressObservation> {
  const cutoff = now - BACKLOG_PRUNE_AGE_MS;
  const fresh = backlog.filter((entry) => {
    const ts = Date.parse(entry.observed_at);
    return Number.isFinite(ts) && ts >= cutoff;
  });
  if (fresh.length <= MAX_BUFFER_ENTRIES) return fresh;
  // Keep the most recent MAX_BUFFER_ENTRIES — observed_at is monotonic
  // for fresh inserts, so the tail is what we want.
  return fresh.slice(-MAX_BUFFER_ENTRIES);
}

export function attachProgressBuffer(deps: ProgressBufferDeps): ProgressBuffer {
  const { bookId, beaconUrl, pushObservations } = deps;

  // Replay anything still in localStorage from a prior mount or unload.
  // Prune first — if the user force-killed the tab N days ago, the same
  // stale entry would otherwise re-fire on every mount forever (server
  // stale-drops it, but that's bytes wasted on every page load). Persist
  // the pruned form back so the cleanup survives even if no observation
  // happens this mount.
  const initial = pruneBacklog(readBacklog(bookId), Date.now());
  writeBacklog(bookId, initial);
  if (initial.length > 0) {
    try {
      pushObservations(initial);
    } catch {
      // pushEvent shouldn't throw; if it does, sendBeacon still owns the
      // durable path and we fall back on next visibilitychange.
    }
  }

  function append(obs: ProgressObservation): void {
    const now = Date.now();
    const merged = pruneBacklog([...readBacklog(bookId), obs], now);
    writeBacklog(bookId, merged);
  }

  function flushViaBeacon(): void {
    const backlog = readBacklog(bookId);
    if (backlog.length === 0) return;
    if (typeof navigator === "undefined" || !navigator.sendBeacon) return;
    const body = new Blob([JSON.stringify({ observations: backlog })], {
      type: "application/json",
    });
    const accepted = navigator.sendBeacon(beaconUrl, body);
    if (accepted) {
      // sendBeacon's "accepted" only means the browser queued the request,
      // not that the server received it. But the request has the same
      // observation payload the server's idempotent `observe!/1` already
      // tolerates as a duplicate, so clearing locally is safe — even if
      // the beacon fails, the next observe will re-seed the buffer.
      writeBacklog(bookId, []);
    }
  }

  function onVisibilityHidden(): void {
    if (document.visibilityState === "hidden") flushViaBeacon();
  }

  // pagehide is more reliable than visibilitychange on iOS Safari for
  // tab close + bfcache eviction. Both are registered; flushViaBeacon is
  // idempotent on an empty backlog.
  document.addEventListener("visibilitychange", onVisibilityHidden);
  window.addEventListener("pagehide", flushViaBeacon);

  return {
    observe(input) {
      const obs: ProgressObservation = {
        ...input,
        observed_at: new Date().toISOString(),
      };
      append(obs);
      try {
        pushObservations([obs]);
      } catch {
        // Same fallback rationale as the initial replay above.
      }
    },
    detach() {
      document.removeEventListener("visibilitychange", onVisibilityHidden);
      window.removeEventListener("pagehide", flushViaBeacon);
    },
  };
}
