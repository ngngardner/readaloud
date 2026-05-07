declare const __brand: unique symbol;
type Brand<T, B> = T & { readonly [__brand]: B };

export type ChapterId = Brand<string, "ChapterId">;
export type WordIndex = Brand<number, "WordIndex">;
export type Milliseconds = Brand<number, "Milliseconds">;

// Branded-type constructors are the canonical TS pattern: there is no other
// way to mint a Brand<T, B> from a T. Suppressed locally; do NOT generalize.
// ast-grep-ignore: no-as-cast
export const ChapterId = (s: string): ChapterId => s as ChapterId;
// ast-grep-ignore: no-as-cast
export const WordIndex = (n: number): WordIndex => n as WordIndex;
// ast-grep-ignore: no-as-cast
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

// Strictly-typed JSON tree. Replaces ad-hoc `unknown` at parse boundaries —
// downstream code must narrow with typeof / Array.isArray before reading
// fields, which is exactly the discipline `unknown` was supposed to enforce
// but routinely escaped via `as`.
export type JsonValue =
  | string
  | number
  | boolean
  | null
  | ReadonlyArray<JsonValue>
  | { readonly [k: string]: JsonValue };

// JSON.parse is typed `(s: string) => any`; `any` widens to JsonValue
// without a cast, which is the whole point of routing parses through here.
export function parseJson(s: string): JsonValue {
  return JSON.parse(s);
}

// User-defined predicate for "is this string one of the literals in this
// readonly tuple". Lets callers narrow `string` to a literal-union without
// the `(TUPLE as readonly string[]).includes(s)` cast workaround.
export function isOneOf<T extends string>(
  haystack: readonly T[],
  needle: string,
): needle is T {
  return haystack.some((x) => x === needle);
}

export function isJsonObject(
  v: JsonValue,
): v is { readonly [k: string]: JsonValue } {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

export function parseWordTimings(json: JsonValue): ReadonlyArray<WordTiming> {
  if (!isJsonObject(json)) return [];
  const timings = json.timings;
  if (!Array.isArray(timings)) return [];
  const out: WordTiming[] = [];
  for (const t of timings) {
    if (!isJsonObject(t)) continue;
    const startMs = t.start_ms;
    const endMs = t.end_ms;
    if (typeof startMs !== "number" || typeof endMs !== "number") continue;
    out.push({ startMs: Milliseconds(startMs), endMs: Milliseconds(endMs) });
  }
  return out;
}

export function parseChapters(
  jsonString: string | undefined,
): ReadonlyArray<Chapter> {
  if (!jsonString) return [];
  let json: JsonValue;
  try {
    json = parseJson(jsonString);
  } catch {
    return [];
  }
  if (!Array.isArray(json)) return [];
  const out: Chapter[] = [];
  for (const c of json) {
    if (!isJsonObject(c)) continue;
    if (typeof c.id !== "string") continue;
    if (typeof c.number !== "number") continue;
    const title = typeof c.title === "string" ? c.title : null;
    out.push({ id: ChapterId(c.id), title, number: c.number });
  }
  return out;
}
