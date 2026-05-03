import { defineHook } from "../lib/hook";

const THEME_STORAGE_KEY = "phx:theme";

export const ThemeHook = defineHook((ctx) => {
  ctx.on(window, "readaloud:set-theme", ({ theme }) => {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem(THEME_STORAGE_KEY, theme);
  });
});
