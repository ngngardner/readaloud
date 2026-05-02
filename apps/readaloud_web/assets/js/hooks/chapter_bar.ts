import { defineHook } from "../lib/hook";
import { attachScrubber, fractionAt } from "../lib/scrubber";
import { type Chapter, parseChapters } from "../lib/types";

interface ChapterBarDataset {
  currentIndex: string;
  totalChapters: string;
  chapters: string;
  bookId: string;
}

export const ChapterBarHook = defineHook<HTMLDivElement, ChapterBarDataset>(
  (ctx) => {
    const chapters = parseChapters(ctx.dataset.chapters);
    const currentIndex = Number.parseInt(ctx.dataset.currentIndex ?? "0", 10);
    const totalChapters = Number.parseInt(ctx.dataset.totalChapters ?? "0", 10);

    const scrubberEl = ctx.el.querySelector<HTMLElement>(
      "[data-chapter-scrubber]",
    );
    const fill = ctx.el.querySelector<HTMLElement>("[data-scrubber-fill]");
    const thumb = ctx.el.querySelector<HTMLElement>("[data-scrubber-thumb]");
    const tooltip = ctx.el.querySelector<HTMLElement>(
      "[data-scrubber-tooltip]",
    );
    const strip = ctx.el.querySelector<HTMLElement>("[data-chapter-strip]");
    const indicator = document.getElementById("chapter-indicator");

    const setScrubberPosition = (index: number): void => {
      const pct = totalChapters > 1 ? (index / (totalChapters - 1)) * 100 : 0;
      if (fill) fill.style.width = `${pct}%`;
      if (thumb) thumb.style.left = `${pct}%`;
    };

    const scrollStripToIndex = (index: number): void => {
      if (!strip) return;
      const pill = strip.children[index];
      if (!(pill instanceof HTMLElement)) return;
      const stripRect = strip.getBoundingClientRect();
      const pillRect = pill.getBoundingClientRect();
      strip.scrollTo({
        left: pill.offsetLeft - stripRect.width / 2 + pillRect.width / 2,
        behavior: "smooth",
      });
    };

    const indexAt = (clientX: number): number => {
      if (!scrubberEl) return 0;
      return Math.round(fractionAt(scrubberEl, clientX) * (totalChapters - 1));
    };

    const showTooltip = (idx: number, clientX: number): void => {
      const ch: Chapter | undefined = chapters[idx];
      if (!ch || !tooltip || !scrubberEl) return;
      const label = ch.title ?? `Chapter ${ch.number}`;
      tooltip.textContent = `${idx + 1}. ${label}`;
      tooltip.classList.remove("hidden");
      const rect = scrubberEl.getBoundingClientRect();
      tooltip.style.left = `${((clientX - rect.left) / rect.width) * 100}%`;
    };

    const hideTooltip = (): void => tooltip?.classList.add("hidden");

    const jumpTo = (idx: number): void => {
      const target = chapters[idx];
      const current = chapters[currentIndex];
      if (!target || target.id === current?.id) return;
      ctx.pushEvent("jump_to_chapter", { chapter_id: target.id });
    };

    setScrubberPosition(currentIndex);
    scrollStripToIndex(currentIndex);

    if (scrubberEl) {
      const dispose = attachScrubber<number>({
        el: scrubberEl,
        indexAt,
        preview: (idx, clientX) => {
          setScrubberPosition(idx);
          scrollStripToIndex(idx);
          showTooltip(idx, clientX);
        },
        previewEnd: hideTooltip,
        commit: jumpTo,
      });
      ctx.onDestroy(dispose);
    }

    let isOpen = false;
    const open = (): void => {
      ctx.el.classList.remove("scale-y-0", "opacity-0", "pointer-events-none");
      ctx.el.classList.add("scale-y-100", "opacity-100");
      isOpen = true;
    };
    const close = (): void => {
      ctx.el.classList.add("scale-y-0", "opacity-0", "pointer-events-none");
      ctx.el.classList.remove("scale-y-100", "opacity-100");
      isOpen = false;
    };
    const toggle = (): void => {
      if (isOpen) close();
      else open();
    };

    if (indicator) ctx.on(indicator, "click", toggle);

    ctx.on(window, "chapter-bar-close", () => {
      isOpen = false;
    });

    ctx.on(document, "click", (e) => {
      if (!isOpen) return;
      const target = e.target;
      if (!(target instanceof Node)) return;
      if (ctx.el.contains(target)) return;
      if (target instanceof Element && target.id === "chapter-indicator")
        return;
      close();
    });

    for (const pill of ctx.el.querySelectorAll<HTMLElement>(
      "[data-chapter-pill]",
    )) {
      ctx.on(pill, "click", () => {
        const idx = Number.parseInt(pill.dataset.chapterPill ?? "-1", 10);
        jumpTo(idx);
      });
    }
  },
);
