// Client-side durable buffer for audio-player diagnostic events.
//
// Same delivery architecture as progress_buffer (which owns reading
// *position*; this owns playback *diagnostics*): every event gets two
// paths to the server —
//   1. `pushEvent("player_events")` over the WS (immediate, optimistic)
//   2. `navigator.sendBeacon` to /api/books/:id/player-events, fired on
//      visibility transitions + pagehide
//
// The whole point of this channel is forensics for the sleeping-mobile
// autoplay bugs: when the screen locks, the WS suspends but the audio
// session (and this hook's event handlers) keep running. Events recorded
// while the socket is dead sit in localStorage and drain via beacon on the
// next visibility transition, or via WS replay on the next mount.
//
// Unlike progress observations, events are NOT idempotent server-side —
// a re-delivered event double-counts in Prometheus. We accept that: the
// prune window is short, the server treats counter rates as approximate,
// and every log line carries the client `at` timestamp so duplicates are
// trivially identifiable in Loki. Losing the last events before a phone
// slept would cost far more than a few duplicate counts.

import type { PlayerEventDetailValue, PlayerEventPayload } from "./events";
import { isJsonObject, type JsonValue, parseJson } from "./types";

export interface PlayerEventBuffer {
  record(
    event: string,
    fields?: {
      readonly chapter_id?: string;
      readonly position_ms?: number;
      readonly detail?: Readonly<Record<string, PlayerEventDetailValue>>;
    },
  ): void;
  detach(): void;
}

interface PlayerEventBufferDeps {
  readonly bookId: number;
  readonly beaconUrl: string;
  readonly pushEvents: (events: ReadonlyArray<PlayerEventPayload>) => void;
}

const STORAGE_KEY_PREFIX = "readaloud-player-events:";
const MAX_BUFFER_ENTRIES = 100;
const BACKLOG_PRUNE_AGE_MS = 120_000;

function storageKey(bookId: number): string {
  return `${STORAGE_KEY_PREFIX}${bookId}`;
}

function isDetailValue(v: JsonValue | undefined): v is PlayerEventDetailValue {
  return (
    v === null ||
    typeof v === "string" ||
    typeof v === "number" ||
    typeof v === "boolean"
  );
}

function parseEvent(v: JsonValue): PlayerEventPayload | null {
  if (!isJsonObject(v)) return null;
  if (typeof v.event !== "string") return null;
  if (typeof v.at !== "string") return null;
  const out: {
    -readonly [K in keyof PlayerEventPayload]: PlayerEventPayload[K];
  } = { event: v.event, at: v.at };
  if (typeof v.chapter_id === "string") out.chapter_id = v.chapter_id;
  if (typeof v.position_ms === "number") out.position_ms = v.position_ms;
  if (v.detail !== undefined && isJsonObject(v.detail)) {
    const detail: Record<string, PlayerEventDetailValue> = {};
    for (const [key, value] of Object.entries(v.detail)) {
      if (isDetailValue(value)) detail[key] = value;
    }
    out.detail = detail;
  }
  return out;
}

function readBacklog(bookId: number): ReadonlyArray<PlayerEventPayload> {
  const raw = localStorage.getItem(storageKey(bookId));
  if (!raw) return [];
  try {
    const json = parseJson(raw);
    if (!Array.isArray(json)) return [];
    const out: PlayerEventPayload[] = [];
    for (const entry of json) {
      const event = parseEvent(entry);
      if (event) out.push(event);
    }
    return out;
  } catch {
    return [];
  }
}

function writeBacklog(
  bookId: number,
  backlog: ReadonlyArray<PlayerEventPayload>,
): void {
  if (backlog.length === 0) {
    localStorage.removeItem(storageKey(bookId));
    return;
  }
  localStorage.setItem(storageKey(bookId), JSON.stringify(backlog));
}

function pruneBacklog(
  backlog: ReadonlyArray<PlayerEventPayload>,
  now: number,
): ReadonlyArray<PlayerEventPayload> {
  const cutoff = now - BACKLOG_PRUNE_AGE_MS;
  const fresh = backlog.filter((entry) => {
    const ts = Date.parse(entry.at);
    return Number.isFinite(ts) && ts >= cutoff;
  });
  if (fresh.length <= MAX_BUFFER_ENTRIES) return fresh;
  return fresh.slice(-MAX_BUFFER_ENTRIES);
}

export function attachPlayerEventBuffer(
  deps: PlayerEventBufferDeps,
): PlayerEventBuffer {
  const { bookId, beaconUrl, pushEvents } = deps;

  // Replay anything still buffered from a prior mount or unload — this is
  // how events recorded while a locked phone's WS was dead reach the
  // server after the LV re-mounts on wake.
  const initial = pruneBacklog(readBacklog(bookId), Date.now());
  writeBacklog(bookId, initial);
  if (initial.length > 0) {
    try {
      pushEvents(initial);
    } catch {
      // pushEvent shouldn't throw; if it does, the beacon path still owns
      // durability on the next visibility transition.
    }
  }

  function append(event: PlayerEventPayload): void {
    const merged = pruneBacklog([...readBacklog(bookId), event], Date.now());
    writeBacklog(bookId, merged);
  }

  function flushViaBeacon(): void {
    const backlog = readBacklog(bookId);
    if (backlog.length === 0) return;
    if (typeof navigator === "undefined" || !navigator.sendBeacon) return;
    const body = new Blob([JSON.stringify({ events: backlog })], {
      type: "application/json",
    });
    if (navigator.sendBeacon(beaconUrl, body)) {
      writeBacklog(bookId, []);
    }
  }

  // Flush on BOTH visibility transitions: `hidden` is the canonical
  // last-chance moment, and `visible` drains anything recorded while the
  // screen was locked without waiting for the WS to re-establish.
  function onVisibilityChange(): void {
    flushViaBeacon();
  }

  document.addEventListener("visibilitychange", onVisibilityChange);
  window.addEventListener("pagehide", flushViaBeacon);

  return {
    record(event, fields) {
      const payload: PlayerEventPayload = {
        event,
        at: new Date().toISOString(),
        ...fields,
      };
      append(payload);
      try {
        pushEvents([payload]);
      } catch {
        // Same fallback rationale as the initial replay above.
      }
    },
    detach() {
      document.removeEventListener("visibilitychange", onVisibilityChange);
      window.removeEventListener("pagehide", flushViaBeacon);
    },
  };
}
