import { defineHook } from "../lib/hook";

function isEditableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return (
    target.tagName === "INPUT" ||
    target.tagName === "TEXTAREA" ||
    target.isContentEditable
  );
}

export const KeyboardShortcutsHook = defineHook((ctx) => {
  ctx.on(window, "keydown", (e) => {
    if (isEditableTarget(e.target)) return;

    switch (e.key) {
      case " ":
        e.preventDefault();
        ctx.dispatch("audio:toggle-playback");
        return;
      case "ArrowLeft":
        e.preventDefault();
        ctx.pushEvent("prev_chapter");
        return;
      case "ArrowRight":
        e.preventDefault();
        ctx.pushEvent("next_chapter");
        return;
      case "+":
      case "=":
        e.preventDefault();
        ctx.dispatch("audio:change-speed", { direction: "up" });
        return;
      case "-":
        e.preventDefault();
        ctx.dispatch("audio:change-speed", { direction: "down" });
        return;
      case "Escape":
        e.preventDefault();
        ctx.dispatch("toggle-pill");
        return;
      case "m":
        e.preventDefault();
        ctx.dispatch("audio:toggle-mute");
        return;
      default:
        return;
    }
  });
});
