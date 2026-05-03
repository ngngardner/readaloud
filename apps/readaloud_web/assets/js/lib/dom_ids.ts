// Cross-runtime contract: every ID here is rendered by the LV templates.
// Renaming any value MUST be matched in apps/readaloud_web/lib/.../live/*.ex
// (grep for the literal string). Hooks may not reach across hook boundaries
// via raw document.getElementById — go through requireElement so a missing
// or wrong-typed element fails loudly in the console instead of silently
// no-opping.

export const DOM_IDS = Object.freeze({
  AUDIO_ELEMENT: "audio-element",
  PLAY_PAUSE_BTN: "play-pause-btn",
  TIME_DISPLAY: "time-display",
  CHAPTER_TEXT: "chapter-text",
  RESYNC_BTN: "resync-btn",
  SPEED_BADGE: "speed-badge",
  AUTO_NEXT_CHAPTER_TOGGLE: "auto-next-chapter-toggle",
});

export function requireElement<T extends HTMLElement>(
  id: string,
  ctor: new (...args: never[]) => T,
): T | null {
  const el = document.getElementById(id);
  if (!el) {
    console.error(`requireElement: #${id} not found`);
    return null;
  }
  if (!(el instanceof ctor)) {
    console.error(
      `requireElement: #${id} is ${el.constructor.name}, expected ${ctor.name}`,
    );
    return null;
  }
  return el;
}

// Optional variant — returns null silently when the element isn't on the page
// (e.g. resync button only renders when audio is loaded). Use this when the
// caller's intent is "if it's there, do something with it."
export function findElement<T extends HTMLElement>(
  id: string,
  ctor: new (...args: never[]) => T,
): T | null {
  const el = document.getElementById(id);
  if (!el) return null;
  if (!(el instanceof ctor)) {
    console.error(
      `findElement: #${id} is ${el.constructor.name}, expected ${ctor.name}`,
    );
    return null;
  }
  return el;
}
