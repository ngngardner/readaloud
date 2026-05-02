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
  "phx:persist_sort": { sort: string };
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

export interface ReadaloudHandleEvents {
  persist_sort: { sort: string };
}
