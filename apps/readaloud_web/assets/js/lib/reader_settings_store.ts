import { PersistedRecord } from "./persisted_record";
import { type JsonValue, isJsonObject, isOneOf } from "./types";

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

function coerce(raw: JsonValue): Partial<ReaderSettings> {
  if (!isJsonObject(raw)) return {};
  const out: { -readonly [K in keyof ReaderSettings]?: ReaderSettings[K] } = {};
  if (
    typeof raw.fontFamily === "string" &&
    isOneOf(FONT_FAMILIES, raw.fontFamily)
  ) {
    out.fontFamily = raw.fontFamily;
  }
  if (typeof raw.fontSize === "number") out.fontSize = raw.fontSize;
  if (typeof raw.lineHeight === "number") out.lineHeight = raw.lineHeight;
  if (typeof raw.maxWidth === "number") out.maxWidth = raw.maxWidth;
  if (typeof raw.autoScroll === "boolean") out.autoScroll = raw.autoScroll;
  if (typeof raw.autoNextChapter === "boolean")
    out.autoNextChapter = raw.autoNextChapter;
  return out;
}

export const readerSettings = new PersistedRecord<ReaderSettings>(
  "readaloud-reader-settings",
  DEFAULTS,
  coerce,
);
