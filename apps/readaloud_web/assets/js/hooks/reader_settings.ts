import { defineHook } from "../lib/hook";
import {
  type ReaderSettings,
  readerSettings,
} from "../lib/reader_settings_store";

const FONT_STACKS: Readonly<Record<ReaderSettings["fontFamily"], string>> = {
  serif: "Georgia, serif",
  sans: "'Inter', sans-serif",
  mono: "ui-monospace, monospace",
};

const RANGE_KEYS = ["fontSize", "lineHeight", "maxWidth"] as const;
type RangeKey = (typeof RANGE_KEYS)[number];

function applySettings(s: Readonly<ReaderSettings>): void {
  const content = document.getElementById("reader-content");
  if (content) content.style.maxWidth = `${s.maxWidth}px`;

  const article = document.getElementById("chapter-text");
  if (article) {
    article.style.fontFamily = FONT_STACKS[s.fontFamily];
    article.style.fontSize = `${s.fontSize}px`;
    article.style.lineHeight = String(s.lineHeight);
  }
}

export const ReaderSettingsHook = defineHook((ctx) => {
  applySettings(readerSettings.get());
  syncControls(readerSettings.get());

  const popover = document.getElementById("reader-settings");
  if (popover) {
    for (const btn of popover.querySelectorAll<HTMLElement>(
      "[data-font-family]",
    )) {
      ctx.on(btn, "click", () => {
        const ff = btn.dataset.fontFamily;
        if (ff === "serif" || ff === "sans" || ff === "mono") {
          readerSettings.set({ fontFamily: ff });
        }
      });
    }

    for (const input of popover.querySelectorAll<HTMLInputElement>(
      "input[type=range][name]",
    )) {
      const key = input.name;
      if (!isRangeKey(key)) continue;
      ctx.on(input, "input", () => {
        readerSettings.set({
          [key]: Number.parseFloat(input.value),
        } as Partial<ReaderSettings>);
      });
    }
  }

  const autoNext = document.getElementById("auto-next-chapter-toggle");
  if (autoNext instanceof HTMLInputElement) {
    ctx.on(autoNext, "change", () => {
      readerSettings.set({ autoNextChapter: autoNext.checked });
    });
  }

  const unsubscribe = readerSettings.subscribe((s) => {
    applySettings(s);
  });
  ctx.onDestroy(unsubscribe);
});

function isRangeKey(s: string): s is RangeKey {
  return (RANGE_KEYS as ReadonlyArray<string>).includes(s);
}

function syncControls(s: Readonly<ReaderSettings>): void {
  const popover = document.getElementById("reader-settings");
  if (popover) {
    for (const key of RANGE_KEYS) {
      const input = popover.querySelector<HTMLInputElement>(
        `input[type=range][name="${key}"]`,
      );
      if (input) input.value = String(s[key]);
    }
  }
  const toggle = document.getElementById("auto-next-chapter-toggle");
  if (toggle instanceof HTMLInputElement) toggle.checked = s.autoNextChapter;
}
