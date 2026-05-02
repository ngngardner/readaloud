import { defineHook } from "../lib/hook";

export const DragDropHook = defineHook<HTMLDivElement>((ctx) => {
  const overlay = ctx.el.querySelector<HTMLElement>("[data-drop-overlay]");
  const fileInput = ctx.el.querySelector<HTMLInputElement>("input[type=file]");

  const showOverlay = (e: DragEvent): void => {
    e.preventDefault();
    overlay?.classList.remove("hidden");
  };
  const hideOverlay = (e: DragEvent): void => {
    e.preventDefault();
    overlay?.classList.add("hidden");
  };

  ctx.on(ctx.el, "dragenter", showOverlay);
  ctx.on(ctx.el, "dragover", showOverlay);
  ctx.on(ctx.el, "dragleave", hideOverlay);
  ctx.on(ctx.el, "drop", (e) => {
    hideOverlay(e);
    const files = e.dataTransfer?.files;
    if (!files || files.length === 0 || !fileInput) return;
    const dt = new DataTransfer();
    for (const f of files) dt.items.add(f);
    fileInput.files = dt.files;
    fileInput.dispatchEvent(new Event("change", { bubbles: true }));
  });
});
