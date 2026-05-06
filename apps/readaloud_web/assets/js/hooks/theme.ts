import { defineHook } from "../lib/hook";

const THEME_STORAGE_KEY = "phx:theme";

function syncActiveSwatches(theme: string): void {
  for (const el of document.querySelectorAll<HTMLElement>("[data-set-theme]")) {
    el.classList.toggle("active", el.dataset.setTheme === theme);
  }
}

export const ThemeHook = defineHook((ctx) => {
  syncActiveSwatches(
    document.documentElement.getAttribute("data-theme") ?? "dark",
  );
  ctx.on(window, "readaloud:set-theme", ({ theme }) => {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem(THEME_STORAGE_KEY, theme);
    syncActiveSwatches(theme);
  });
});
