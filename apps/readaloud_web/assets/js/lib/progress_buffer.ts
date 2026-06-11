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

import { beaconBestEffort, flushConfirmed } from "./confirmed_flush";
import { type JsonValue, isJsonObject, parseJson } from "./types";

export interface ProgressObservation {
  readonly chapter_id: string;
  readonly audio_position_ms?: number;
  readonly scroll_position?: number;
  readonly observed_at: string;
  // Explicit chapter pivot (see ProgressObservationPayload in events.ts).
  // Must survive the localStorage round-trip: a buffered pivot replayed
  // after reconnect is exactly the case the server reconciler exists for.
  readonly pivot?: true;
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
// Wide enough to carry a commute-length offline gap: the 2026-06-11
// incident's final chapter pivot was recorded 8 minutes before the next
// mount and the old 60s window pruned it before it could be replayed —
// the server never learned the user had moved on. Position ticks are
// individually cheap; the pivots they travel with are not.
const MAX_BUFFER_ENTRIES = 150;
const BACKLOG_PRUNE_AGE_MS = 10 * 60_000;

function storageKey(bookId: number): string {
  return `${STORAGE_KEY_PREFIX}${bookId}`;
}

// --- Last-known-position cache ----------------------------------------
// The queue above is a delivery buffer: entries are cleared the moment a
// beacon is *queued* (not received). That's correct for delivery — the
// server's observe! is idempotent — but it means a page load right after
// a pagehide flush can race the beacon to the server and restore a stale
// position (the 2026-06-11 incident: beacon carrying 5.8s arrived 6s
// after the new page had already mounted at 0:00).
//
// This cache is the client's own memory of where playback last was:
// written on every observation, never cleared, read at player mount as a
// candidate alongside the server's initial position. Same-chapter only,
// recency-bounded — across devices or after a long gap the server row is
// the better authority.

export interface LastPosition {
  readonly chapter_id: string;
  readonly position_ms: number;
  readonly at_ms: number;
}

const LAST_POSITION_KEY_PREFIX = "readaloud-last-position:";

function lastPositionKey(bookId: number): string {
  return `${LAST_POSITION_KEY_PREFIX}${bookId}`;
}

export function writeLastPosition(
  bookId: number,
  chapterId: string,
  positionMs: number,
): void {
  const entry: LastPosition = {
    chapter_id: chapterId,
    position_ms: positionMs,
    at_ms: Date.now(),
  };
  try {
    localStorage.setItem(lastPositionKey(bookId), JSON.stringify(entry));
  } catch {
    // Quota/private-mode failures just mean no client-side restore.
  }
}

export function readLastPosition(bookId: number): LastPosition | null {
  const raw = localStorage.getItem(lastPositionKey(bookId));
  if (!raw) return null;
  try {
    const json = parseJson(raw);
    if (!isJsonObject(json)) return null;
    if (typeof json.chapter_id !== "string") return null;
    if (typeof json.position_ms !== "number") return null;
    if (typeof json.at_ms !== "number") return null;
    return {
      chapter_id: json.chapter_id,
      position_ms: json.position_ms,
      at_ms: json.at_ms,
    };
  } catch {
    return null;
  }
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
  if (v.pivot === true) {
    out.pivot = true;
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

  // Replay anything still in localStorage from a prior mount or unload —
  // BEFORE pruning, so the final observations of a session that died
  // offline (the chapter pivot especially) get at least one delivery
  // attempt instead of being silently aged out. The pruned form is
  // persisted right after, so a stale entry re-fires at most once, not
  // on every mount forever.
  const initialBacklog = readBacklog(bookId);
  if (initialBacklog.length > 0) {
    try {
      pushObservations(initialBacklog);
    } catch {
      // pushEvent shouldn't throw; if it does, the HTTP path still owns
      // durability on the next flush trigger.
    }
  }
  writeBacklog(bookId, pruneBacklog(initialBacklog, Date.now()));

  function append(obs: ProgressObservation): void {
    const now = Date.now();
    const merged = pruneBacklog([...readBacklog(bookId), obs], now);
    writeBacklog(bookId, merged);
  }

  const entryKey = (o: ProgressObservation): string =>
    `${o.observed_at} ${o.chapter_id}`;

  // Confirmed-delivery flush — only observations the server 2xx'd leave
  // the backlog. The old sendBeacon flush cleared on "queued", which is a
  // silent drop when the network is down; "the next observe re-seeds the
  // buffer" doesn't hold for the *last* observations of a session (the
  // 2026-06-11 final pivot had no next observe).
  let flushInFlight = false;
  function flush(): void {
    if (flushInFlight) return;
    const backlog = readBacklog(bookId);
    if (backlog.length === 0) return;
    flushInFlight = true;
    flushConfirmed(beaconUrl, "observations", backlog)
      .then((delivered) => {
        if (delivered.length === 0) return;
        const deliveredKeys = new Set(delivered.map(entryKey));
        writeBacklog(
          bookId,
          readBacklog(bookId).filter((o) => !deliveredKeys.has(entryKey(o))),
        );
      })
      .finally(() => {
        flushInFlight = false;
      });
  }
  flush();

  function onVisibilityChange(): void {
    // `hidden` is the canonical last-chance flush; `visible` drains
    // observations recorded while the screen was locked without waiting
    // for the WS to re-establish.
    flush();
  }

  function onOnline(): void {
    flush();
  }

  // pagehide is more reliable than visibilitychange on iOS Safari for
  // tab close + bfcache eviction, but may not leave enough page lifetime
  // for a confirmed round-trip — so also fire a best-effort beacon
  // WITHOUT clearing (observe!/1 is idempotent; duplicates are fine,
  // silent loss is not).
  function onPageHide(): void {
    flush();
    beaconBestEffort(beaconUrl, "observations", readBacklog(bookId));
  }

  document.addEventListener("visibilitychange", onVisibilityChange);
  window.addEventListener("pagehide", onPageHide);
  window.addEventListener("online", onOnline);

  return {
    observe(input) {
      const obs: ProgressObservation = {
        ...input,
        observed_at: new Date().toISOString(),
      };
      if (typeof obs.audio_position_ms === "number") {
        writeLastPosition(bookId, obs.chapter_id, obs.audio_position_ms);
      }
      append(obs);
      try {
        pushObservations([obs]);
      } catch {
        // Same fallback rationale as the initial replay above.
      }
    },
    detach() {
      document.removeEventListener("visibilitychange", onVisibilityChange);
      window.removeEventListener("pagehide", onPageHide);
      window.removeEventListener("online", onOnline);
    },
  };
}
