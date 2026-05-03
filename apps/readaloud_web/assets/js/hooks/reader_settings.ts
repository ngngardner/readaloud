import { defineHook } from "../lib/hook";
import { DOM_IDS } from "../lib/dom_ids";
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

function isRangeKey(s: string): s is RangeKey {
  return (RANGE_KEYS as ReadonlyArray<string>).includes(s);
}

// Lives on #reader-content. Owns the visual application of reader settings
// to its own subtree (the chapter article). Subscribes to the settings
// store; controls are wired up by ReaderSettingsControlsHook on the popover.
export const ReaderStylesHook = defineHook<HTMLDivElement>((ctx) => {
  const apply = (s: Readonly<ReaderSettings>): void => {
    ctx.el.style.maxWidth = `${s.maxWidth}px`;
    const article = ctx.el.querySelector<HTMLElement>(
      `#${DOM_IDS.CHAPTER_TEXT}`,
    );
    if (article) {
      article.style.fontFamily = FONT_STACKS[s.fontFamily];
      article.style.fontSize = `${s.fontSize}px`;
      article.style.lineHeight = String(s.lineHeight);
    }
  };

  apply(readerSettings.get());
  ctx.onDestroy(readerSettings.subscribe(apply));
});

// Lives on #reader-settings (the popover). Owns the form controls inside
// itself (font buttons, range sliders, auto-next toggle). Writes to the
// settings store; ReaderStylesHook reads from it.
export const ReaderSettingsControlsHook = defineHook<HTMLDivElement>((ctx) => {
  for (const btn of ctx.el.querySelectorAll<HTMLElement>(
    "[data-font-family]",
  )) {
    ctx.on(btn, "click", () => {
      const ff = btn.dataset.fontFamily;
      if (ff === "serif" || ff === "sans" || ff === "mono") {
        readerSettings.set({ fontFamily: ff });
      }
    });
  }

  for (const input of ctx.el.querySelectorAll<HTMLInputElement>(
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

  const autoNext = ctx.el.querySelector<HTMLInputElement>(
    `#${DOM_IDS.AUTO_NEXT_CHAPTER_TOGGLE}`,
  );
  if (autoNext) {
    ctx.on(autoNext, "change", () => {
      readerSettings.set({ autoNextChapter: autoNext.checked });
    });
  }

  syncControls(readerSettings.get());

  function syncControls(s: Readonly<ReaderSettings>): void {
    for (const key of RANGE_KEYS) {
      const input = ctx.el.querySelector<HTMLInputElement>(
        `input[type=range][name="${key}"]`,
      );
      if (input) input.value = String(s[key]);
    }
    if (autoNext) autoNext.checked = s.autoNextChapter;
  }
});
