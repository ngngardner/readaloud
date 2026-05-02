import { defineHook } from "../lib/hook";

const COLLAPSED_CLASS = "max-sm:translate-x-[-100%]";

export const SidebarHook = defineHook<HTMLElement>((ctx) => {
  const sidebar = ctx.el;
  const toggle = document.getElementById("sidebar-toggle");
  const backdrop = document.getElementById("sidebar-backdrop");
  const labels = sidebar.querySelectorAll<HTMLElement>(
    "span.whitespace-nowrap",
  );

  const setLabelOpacity = (opacity: "0" | "1"): void => {
    for (const el of labels) el.style.opacity = opacity;
  };

  ctx.on(sidebar, "mouseenter", () => setLabelOpacity("1"));
  ctx.on(sidebar, "mouseleave", () => setLabelOpacity("0"));

  if (toggle) {
    ctx.on(toggle, "click", () => {
      const isOpen = !sidebar.classList.contains(COLLAPSED_CLASS);
      if (isOpen) {
        sidebar.classList.add(COLLAPSED_CLASS);
        backdrop?.classList.add("hidden");
      } else {
        sidebar.classList.remove(COLLAPSED_CLASS);
        backdrop?.classList.remove("hidden");
        setLabelOpacity("1");
      }
    });
  }

  if (backdrop) {
    ctx.on(backdrop, "click", () => {
      sidebar.classList.add(COLLAPSED_CLASS);
      backdrop.classList.add("hidden");
    });
  }
});
