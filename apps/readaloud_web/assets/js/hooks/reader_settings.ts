import { defineHook } from "../lib/hook";
import { DOM_IDS } from "../lib/dom_ids";
import {
  type ReaderSettings,
  readerSettings,
} from "../lib/reader_settings_store";
import { isOneOf } from "../lib/types";

const FONT_STACKS: Readonly<Record<ReaderSettings["fontFamily"], string>> = {
  serif: "Georgia, serif",
  sans: "'Inter', sans-serif",
  mono: "ui-monospace, monospace",
};

const RANGE_KEYS = ["fontSize", "lineHeight", "maxWidth"] as const;
type RangeKey = (typeof RANGE_KEYS)[number];

function isRangeKey(s: string): s is RangeKey {
  return isOneOf(RANGE_KEYS, s);
}

function setRangeKey(key: RangeKey, value: number): void {
  // Computed-key object literals widen to `{ [k: string]: number }`, which
  // doesn't match Partial<ReaderSettings>. Switch on the literal so each
  // branch builds a typed patch.
  switch (key) {
    case "fontSize":
      readerSettings.set({ fontSize: value });
      return;
    case "lineHeight":
      readerSettings.set({ lineHeight: value });
      return;
    case "maxWidth":
      readerSettings.set({ maxWidth: value });
      return;
  }
}

// Lives on #reader-content. Owns the visual application of reader settings
// to its own subtree (the chapter article). Controls are wired up by
// ReaderSettingsControlsHook on the popover.
export const ReaderStylesHook = defineHook<HTMLDivElement>((ctx) => {
  ctx.bindStore(readerSettings, (s) => {
    ctx.el.style.maxWidth = `${s.maxWidth}px`;
    const article = ctx.el.querySelector<HTMLElement>(
      `#${DOM_IDS.CHAPTER_TEXT}`,
    );
    if (article) {
      article.style.fontFamily = FONT_STACKS[s.fontFamily];
      article.style.fontSize = `${s.fontSize}px`;
      article.style.lineHeight = String(s.lineHeight);
    }
  });
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
      setRangeKey(key, Number.parseFloat(input.value));
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

  ctx.bindStore(readerSettings, (s) => {
    for (const key of RANGE_KEYS) {
      const input = ctx.el.querySelector<HTMLInputElement>(
        `input[type=range][name="${key}"]`,
      );
      if (input) input.value = String(s[key]);
    }
    if (autoNext) autoNext.checked = s.autoNextChapter;
    for (const btn of ctx.el.querySelectorAll<HTMLElement>(
      "[data-font-family]",
    )) {
      btn.classList.toggle("active", btn.dataset.fontFamily === s.fontFamily);
    }
  });

  // Theme swatches live in this popover but the active state is tracked
  // on documentElement (set by ThemeHook + bootstrap inline script). The
  // hook is on app-shell, mounting before LV renders the popover, so it
  // can't see swatches at its own mount time. ctx.onUpdate also covers
  // the morphdom-strip-on-chapter-swap case.
  const syncActiveSwatches = (): void => {
    const current =
      document.documentElement.getAttribute("data-theme") ?? "dark";
    for (const el of ctx.el.querySelectorAll<HTMLElement>("[data-set-theme]")) {
      el.classList.toggle("active", el.dataset.setTheme === current);
    }
  };
  syncActiveSwatches();
  ctx.onUpdate(syncActiveSwatches);
});
