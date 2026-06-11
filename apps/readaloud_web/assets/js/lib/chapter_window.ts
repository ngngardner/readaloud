// Client-side copy of a chapter's nav neighbors — the data the autoplay
// chain consumes at every chapter boundary.
//
// The LV dataset is the primary source for this data, but the dataset is
// a server projection that only advances when a diff arrives over the
// WebSocket. The autoplay chain is explicitly designed to keep running
// with the WS dead (locked phone, commute dead zone) — so consuming the
// dataset directly at `ended` means consuming a projection that may be
// frozen one chapter behind. That is the 2026-06-11 incident: the
// ended-handler's "next" resolved to the chapter that had just finished.
//
// This module types the window and parses the /nav endpoint response
// (`GET /api/books/:b/chapters/:c/nav`), which the player fetches at
// prefetch time — i.e. while the network demonstrably works — so that by
// the time a chapter starts playing, its own neighbors are already local.

import { isJsonObject, type JsonValue } from "./types";

export interface ChapterNavTarget {
  readonly chapterId: string;
  readonly networkUrl: string;
  readonly timingsUrl: string;
  readonly title: string;
}

export interface ChapterWindow {
  readonly next: ChapterNavTarget | null;
  readonly prev: ChapterNavTarget | null;
}

// The /nav URL is derived from the audio URL rather than threaded through
// the dataset: both are served by the same controller and share the
// /api/books/:b/chapters/:c prefix by construction.
export function navUrlFor(audioUrl: string): string {
  return audioUrl.replace(/\/audio$/, "/nav");
}

function parseTarget(v: JsonValue | undefined): ChapterNavTarget | null {
  if (v === undefined || !isJsonObject(v)) return null;
  if (typeof v.chapter_id !== "number" && typeof v.chapter_id !== "string") {
    return null;
  }
  if (typeof v.audio_url !== "string") return null;
  if (typeof v.timings_url !== "string") return null;
  if (typeof v.title !== "string") return null;
  return {
    chapterId: String(v.chapter_id),
    networkUrl: v.audio_url,
    timingsUrl: v.timings_url,
    title: v.title,
  };
}

export function parseChapterWindow(v: JsonValue): ChapterWindow | null {
  if (!isJsonObject(v)) return null;
  return {
    next: parseTarget(v.next),
    prev: parseTarget(v.prev),
  };
}
