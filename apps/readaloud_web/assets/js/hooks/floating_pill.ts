import { defineHook } from "../lib/hook";

function isElementVisible(el: Element): boolean {
  const style = getComputedStyle(el);
  if (style.display === "none") return false;
  if (style.visibility === "hidden") return false;
  if (Number.parseFloat(style.opacity) === 0) return false;
  if (style.pointerEvents === "none") return false;
  return true;
}

function hasOpenPopover(): boolean {
  const popovers = document.querySelectorAll("[data-pill-popover]");
  for (const el of popovers) {
    if (isElementVisible(el)) return true;
  }
  return false;
}

const MOBILE_BREAKPOINT_PX = 640;
const MOBILE_TOUCH_HOLD_MS = 5000;
const DESKTOP_HOVER_HOLD_MS = 3000;
const MOBILE_TOP_AFFORDANCE_PX = 80;

export const FloatingPillHook = defineHook<HTMLDivElement>((ctx) => {
  const pill = ctx.el;
  const isMobile = window.innerWidth < MOBILE_BREAKPOINT_PX;
  let visible = false;
  let hideTimer: number | undefined;

  const show = (): void => {
    pill.classList.remove("opacity-0", "pointer-events-none");
    pill.classList.add("opacity-100");
    visible = true;
  };

  const hide = (): void => {
    if (hasOpenPopover()) return;
    pill.classList.add("opacity-0", "pointer-events-none");
    pill.classList.remove("opacity-100");
    visible = false;
  };

  const resetTimer = (ms: number): void => {
    if (hideTimer !== undefined) clearTimeout(hideTimer);
    hideTimer = window.setTimeout(hide, ms);
  };

  const toggle = (): void => {
    if (visible) hide();
    else show();
    if (visible) resetTimer(MOBILE_TOUCH_HOLD_MS);
  };

  if (isMobile) {
    ctx.on(document, "click", (e) => {
      if (
        e.clientY < MOBILE_TOP_AFFORDANCE_PX &&
        !pill.contains(e.target as Node)
      ) {
        toggle();
      }
    });
    ctx.on(pill, "click", () => resetTimer(MOBILE_TOUCH_HOLD_MS));
  } else {
    ctx.on(document, "mousemove", () => {
      show();
      resetTimer(DESKTOP_HOVER_HOLD_MS);
    });
    ctx.on(pill, "mouseenter", () => {
      if (hideTimer !== undefined) clearTimeout(hideTimer);
    });
    ctx.on(pill, "mouseleave", () => resetTimer(DESKTOP_HOVER_HOLD_MS));
  }

  ctx.on(window, "toggle-pill", toggle);
  ctx.onDestroy(() => {
    if (hideTimer !== undefined) clearTimeout(hideTimer);
  });

  hide();
});
