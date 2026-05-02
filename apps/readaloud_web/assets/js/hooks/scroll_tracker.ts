import { defineHook } from "../lib/hook";
import { scrollFollow } from "../lib/scroll_follow";

interface ScrollTrackerDataset {
  initialScroll?: string;
}

const SCROLL_REPORT_DEBOUNCE_MS = 500;

export const ScrollTrackerHook = defineHook<HTMLElement, ScrollTrackerDataset>(
  (ctx) => {
    const initial = Number.parseFloat(ctx.dataset.initialScroll ?? "0");
    if (initial > 0) {
      requestAnimationFrame(() => {
        const scrollable = ctx.el.scrollHeight - ctx.el.clientHeight;
        if (scrollable > 0) ctx.el.scrollTop = initial * scrollable;
      });
    }

    let scrollTimer: number | undefined;
    ctx.on(ctx.el, "scroll", () => {
      if (scrollTimer !== undefined) clearTimeout(scrollTimer);
      scrollTimer = window.setTimeout(() => {
        const scrollable = ctx.el.scrollHeight - ctx.el.clientHeight;
        const position = scrollable > 0 ? ctx.el.scrollTop / scrollable : 0;
        ctx.pushEvent("scroll", {
          position: Math.min(1, Math.max(0, position)),
        });
        scrollFollow.manualScroll();
      }, SCROLL_REPORT_DEBOUNCE_MS);
    });

    ctx.onDestroy(() => {
      if (scrollTimer !== undefined) clearTimeout(scrollTimer);
    });
  },
);
