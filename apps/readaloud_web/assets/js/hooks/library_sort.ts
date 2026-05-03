import { defineHook } from "../lib/hook";

const STORAGE_KEY = "readaloud-library-sort";

export const LibrarySortHook = defineHook<HTMLFormElement>((ctx) => {
  const select = ctx.el.querySelector<HTMLSelectElement>("select[name=sort]");
  if (!select) return;
  ctx.on(select, "change", () => {
    localStorage.setItem(STORAGE_KEY, select.value);
  });
});
