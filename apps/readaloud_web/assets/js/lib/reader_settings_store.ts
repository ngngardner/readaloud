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

export const readerSettings = new PersistedRecord<ReaderSettings>(
  "readaloud-reader-settings",
  DEFAULTS,
  coerce,
);
