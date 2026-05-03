declare const __brand: unique symbol;
type Brand<T, B> = T & { readonly [__brand]: B };

export type ChapterId = Brand<string, "ChapterId">;
export type WordIndex = Brand<number, "WordIndex">;
export type Milliseconds = Brand<number, "Milliseconds">;

export const ChapterId = (s: string): ChapterId => s as ChapterId;
export const WordIndex = (n: number): WordIndex => n as WordIndex;
export const Milliseconds = (n: number): Milliseconds => n as Milliseconds;

// Cross-runtime contract: chapter text is rendered server-side as
// <span class="word" data-word-index="N">. The Elixir helper that emits the
// span lives at ReadaloudWebWeb.LiveHelpers.word_span/2 — keep both in sync
// if you rename the attribute.
export const WORD_INDEX_ATTR = "data-word-index";

export function wordSelector(index: number): string {
  return `[${WORD_INDEX_ATTR}="${index}"]`;
}

export interface Chapter {
  readonly id: ChapterId;
  readonly title: string | null;
  readonly number: number;
}

export interface WordTiming {
  readonly startMs: Milliseconds;
  readonly endMs: Milliseconds;
}

interface WireWordTiming {
  start_ms: number;
  end_ms: number;
}

interface WireChapter {
  id: string;
  title?: string | null;
  number: number;
}

export function parseWordTimings(json: unknown): ReadonlyArray<WordTiming> {
  if (!json || typeof json !== "object" || !("timings" in json)) return [];
  const wire =
    (json as { timings?: ReadonlyArray<WireWordTiming> }).timings ?? [];
  return wire.map((t) => ({
    startMs: Milliseconds(t.start_ms),
    endMs: Milliseconds(t.end_ms),
  }));
}

export function parseChapters(
  jsonString: string | undefined,
): ReadonlyArray<Chapter> {
  if (!jsonString) return [];
  let wire: ReadonlyArray<WireChapter>;
  try {
    wire = JSON.parse(jsonString) as ReadonlyArray<WireChapter>;
  } catch {
    return [];
  }
  return wire.map((c) => ({
    id: ChapterId(c.id),
    title: c.title ?? null,
    number: c.number,
  }));
}
