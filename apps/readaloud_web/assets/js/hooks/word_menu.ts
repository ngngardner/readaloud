import { WordIndex } from "../lib/types";

const LONG_PRESS_MS = 500;
const MOVE_THRESHOLD_PX = 10;

const MENU_INNER_HTML = `
  <button
    data-word-menu-action="play"
    class="w-full px-3 py-2 text-sm hover:bg-base-300 flex items-center gap-2"
  >
    <span aria-hidden="true">▶</span>
    <span>Play from here</span>
  </button>
`;

export function attachWordMenu(container: HTMLElement | null): () => void {
  if (!container) return () => {};

  const menu = document.createElement("div");
  menu.className =
    "word-menu hidden fixed z-50 bg-base-200 border border-base-content/10 rounded-lg shadow-xl py-1 min-w-[160px] overflow-hidden";
  menu.innerHTML = MENU_INNER_HTML;
  document.body.appendChild(menu);

  let activeWord: HTMLElement | null = null;
  let pressTimer: number | undefined;
  let pressStart: { x: number; y: number } | null = null;

  const close = (): void => {
    menu.classList.add("hidden");
    activeWord = null;
    document.removeEventListener("click", onDocClick);
    document.removeEventListener("touchstart", onDocClick);
  };

  const onDocClick = (e: Event): void => {
    if (e.target instanceof Node && menu.contains(e.target)) return;
    close();
  };

  const open = (word: HTMLElement, x: number, y: number): void => {
    activeWord = word;
    menu.classList.remove("hidden");
    const rect = menu.getBoundingClientRect();
    const top = Math.max(8, y - rect.height - 12);
    const left = Math.max(
      8,
      Math.min(x - rect.width / 2, window.innerWidth - rect.width - 8),
    );
    menu.style.top = `${top}px`;
    menu.style.left = `${left}px`;
    setTimeout(() => {
      document.addEventListener("click", onDocClick);
      document.addEventListener("touchstart", onDocClick, { passive: true });
    }, 0);
  };

  const onMenuClick = (e: MouseEvent): void => {
    const target = e.target;
    if (!(target instanceof Element) || !activeWord) return;
    const btn = target.closest<HTMLElement>("[data-word-menu-action]");
    if (!btn) return;
    const kind = btn.dataset.wordMenuAction;
    const indexStr = activeWord.dataset.wordIndex;
    if (!kind || indexStr === undefined) return;
    const index = WordIndex(Number.parseInt(indexStr, 10));
    if (kind === "play") {
      window.dispatchEvent(
        new CustomEvent("word-action", { detail: { kind: "play", index } }),
      );
    }
    close();
  };

  const findWord = (target: EventTarget | null): HTMLElement | null => {
    if (!(target instanceof Element)) return null;
    return target.closest<HTMLElement>("[data-word-index]");
  };

  const onContextMenu = (e: MouseEvent): void => {
    const word = findWord(e.target);
    if (!word) return;
    e.preventDefault();
    open(word, e.clientX, e.clientY);
  };

  const cancelPress = (): void => {
    if (pressTimer !== undefined) {
      clearTimeout(pressTimer);
      pressTimer = undefined;
    }
    pressStart = null;
  };

  const onTouchStart = (e: TouchEvent): void => {
    const word = findWord(e.target);
    if (!word) return;
    const touch = e.touches[0];
    if (!touch) return;
    pressStart = { x: touch.clientX, y: touch.clientY };
    pressTimer = window.setTimeout(() => {
      pressTimer = undefined;
      if (pressStart) open(word, pressStart.x, pressStart.y);
      pressStart = null;
    }, LONG_PRESS_MS);
  };

  const onTouchMove = (e: TouchEvent): void => {
    if (!pressStart) return;
    const t = e.touches[0];
    if (!t) return;
    const dx = Math.abs(t.clientX - pressStart.x);
    const dy = Math.abs(t.clientY - pressStart.y);
    if (dx > MOVE_THRESHOLD_PX || dy > MOVE_THRESHOLD_PX) cancelPress();
  };

  menu.addEventListener("click", onMenuClick);
  container.addEventListener("contextmenu", onContextMenu);
  container.addEventListener("touchstart", onTouchStart, { passive: true });
  container.addEventListener("touchmove", onTouchMove, { passive: true });
  container.addEventListener("touchend", cancelPress, { passive: true });
  container.addEventListener("touchcancel", cancelPress, { passive: true });

  return function cleanup(): void {
    cancelPress();
    close();
    menu.removeEventListener("click", onMenuClick);
    container.removeEventListener("contextmenu", onContextMenu);
    container.removeEventListener("touchstart", onTouchStart);
    container.removeEventListener("touchmove", onTouchMove);
    container.removeEventListener("touchend", cancelPress);
    container.removeEventListener("touchcancel", cancelPress);
    menu.remove();
  };
}
