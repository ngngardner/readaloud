import type { ChapterId, WordIndex } from "./types";

export interface ReadaloudWindowEvents {
  "audio:toggle-playback": undefined;
  "audio:toggle-mute": undefined;
  "audio:change-speed": { direction: "up" | "down" };
  "audio:playing-changed": { playing: boolean };
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

export interface ReadaloudPushEvents {
  scroll: { position: number };
  audio_position: { position_ms: number };
  next_chapter: Record<string, never>;
  prev_chapter: Record<string, never>;
  jump_to_chapter: { chapter_id: ChapterId };
}

// LV → JS socket pushes. Currently unused; add an entry here before calling
// ctx.handleEvent in a hook so the contract stays typed. Keeping the channel
// declared (even when empty) is the contract — keyof Record<never,never> is
// never, so calls are unreachable until something is added.
export type ReadaloudHandleEvents = Record<never, never>;
