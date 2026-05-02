import { PersistedRecord } from "./persisted_record";

export interface ReaderSettings {
  readonly fontFamily: "serif" | "sans" | "mono";
  readonly fontSize: number;
  readonly lineHeight: number;
  readonly maxWidth: number;
  readonly autoScroll: boolean;
  readonly autoNextChapter: boolean;
}

const DEFAULTS: ReaderSettings = Object.freeze({
  fontFamily: "serif",
  fontSize: 18,
  lineHeight: 1.8,
  maxWidth: 700,
  autoScroll: true,
  autoNextChapter: false,
});

const FONT_FAMILIES = ["serif", "sans", "mono"] as const;

function coerce(raw: unknown): Partial<ReaderSettings> {
  if (!raw || typeof raw !== "object") return {};
  const r = raw as Record<string, unknown>;
  const out: { -readonly [K in keyof ReaderSettings]?: ReaderSettings[K] } = {};
  if (
    typeof r.fontFamily === "string" &&
    (FONT_FAMILIES as ReadonlyArray<string>).includes(r.fontFamily)
  ) {
    out.fontFamily = r.fontFamily as ReaderSettings["fontFamily"];
  }
  if (typeof r.fontSize === "number") out.fontSize = r.fontSize;
  if (typeof r.lineHeight === "number") out.lineHeight = r.lineHeight;
  if (typeof r.maxWidth === "number") out.maxWidth = r.maxWidth;
  if (typeof r.autoScroll === "boolean") out.autoScroll = r.autoScroll;
  if (typeof r.autoNextChapter === "boolean")
    out.autoNextChapter = r.autoNextChapter;
  return out;
}

const store = new PersistedRecord<ReaderSettings>(
  "readaloud-reader-settings",
  DEFAULTS,
  coerce,
);

type SettingsListener = (s: Readonly<ReaderSettings>) => void;
const listeners = new Set<SettingsListener>();

export const readerSettings = {
  get(): Readonly<ReaderSettings> {
    return store.get();
  },
  set(patch: Partial<ReaderSettings>): Readonly<ReaderSettings> {
    const next = store.set(patch);
    for (const fn of listeners) fn(next);
    return next;
  },
  subscribe(fn: SettingsListener): () => void {
    listeners.add(fn);
    return () => listeners.delete(fn);
  },
  defaults: DEFAULTS,
};
