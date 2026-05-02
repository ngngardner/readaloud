import { defineHook } from "../lib/hook";

export const ThemeHook = defineHook(() => {
  // Theme persistence is handled by the inline <script> in root.html.heex.
  // This hook exists as a mount point for JS commands.
});
