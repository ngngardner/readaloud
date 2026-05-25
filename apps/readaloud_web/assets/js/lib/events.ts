import type { ChapterId, WordIndex } from "./types";

export interface ReadaloudWindowEvents {
  "audio:toggle-playback": undefined;
  "audio:toggle-mute": undefined;
  "audio:change-speed": { direction: "up" | "down" };
  "audio:playing-changed": { playing: boolean };
  // Manual chapter nav (floating-pill buttons + keyboard arrows). When the
  // audio player is mounted, it handles these client-side: same-element
  // src swap + history.pushState + buffered progress observation +
  // `pushEvent("next_chapter", { client_owned: true })`. That keeps the
  // OS audio session alive (critical for mobile lock-screen playback) and
  // avoids the bug where push_patch swaps page state but leaves the
  // <audio> element playing the previous chapter. If no audio target is
  // available (next chapter has no audio yet) the hook falls back to the
  // server-owned phx-click path.
  "audio:nav-next-chapter": undefined;
  "audio:nav-prev-chapter": undefined;
  "manual-scroll": undefined;
  "auto-scroll-start": undefined;
  "auto-scroll-end": undefined;
  "word-action": { kind: "play"; index: WordIndex };
  "toggle-pill": undefined;
  "chapter-bar-close": undefined;
  "readaloud:set-theme": { theme: string };
  "phx:live_reload:attached": LiveReloader;
}

export interface LiveReloader {
  enableServerLogs(): void;
  disableServerLogs(): void;
  openEditorAtCaller(target: EventTarget | null): void;
  openEditorAtDef(target: EventTarget | null): void;
}

// Wire shape of a single position observation. `chapter_id` is sent as
// a string (matching `jump_to_chapter`'s ChapterId convention); the server
// `Observation.from_map/2` accepts both string and integer.
export interface ProgressObservationPayload {
  readonly chapter_id: string;
  readonly audio_position_ms?: number;
  readonly scroll_position?: number;
  readonly observed_at: string;
}

export interface ReadaloudPushEvents {
  scroll: { position: number };
  // Single durable channel for client-owned position observations. Always
  // batched (the JS-side `progressBuffer` flushes one or many at a time;
  // the server applies them in `observed_at` order with stale-drop
  // semantics, so live + buffered drains can interleave safely).
  progress_observations: {
    observations: ReadonlyArray<ProgressObservationPayload>;
  };
  // client_owned: the audio_player JS hook owns BOTH the URL update
  // (via history.pushState) AND the persistence write (via the progress
  // buffer). The server should reload chapter assigns only — skipping
  // its own push_patch (would create a duplicate history entry on a
  // connected client) and skipping its own observe! (would race with
  // the buffered drain). Manual button clicks via phx-click omit the
  // flag and get the normal server-driven path.
  next_chapter: { client_owned?: true };
  prev_chapter: { client_owned?: true };
  jump_to_chapter: { chapter_id: ChapterId };
}

// LV → JS socket pushes. Currently unused; add an entry here before calling
// ctx.handleEvent in a hook so the contract stays typed. Keeping the channel
// declared (even when empty) is the contract — keyof Record<never,never> is
// never, so calls are unreachable until something is added.
export type ReadaloudHandleEvents = Record<never, never>;
