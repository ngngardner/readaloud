export interface ScrubberOptions<T> {
  readonly el: HTMLElement;
  readonly indexAt: (clientX: number) => T;
  readonly preview: (value: T, clientX: number) => void;
  readonly commit: (value: T) => void;
  readonly previewEnd?: () => void;
}

export function attachScrubber<T>(opts: ScrubberOptions<T>): () => void {
  const { el, indexAt, preview, commit, previewEnd } = opts;
  let isDragging = false;

  const previewAt = (clientX: number): T => {
    const v = indexAt(clientX);
    preview(v, clientX);
    return v;
  };

  const onMouseDown = (e: MouseEvent): void => {
    isDragging = true;
    previewAt(e.clientX);
    e.preventDefault();
  };
  const onMouseMove = (e: MouseEvent): void => {
    if (isDragging) previewAt(e.clientX);
  };
  const onMouseUp = (e: MouseEvent): void => {
    if (!isDragging) return;
    isDragging = false;
    previewEnd?.();
    commit(indexAt(e.clientX));
  };
  const onClick = (e: MouseEvent): void => {
    if (!isDragging) commit(indexAt(e.clientX));
  };

  const onTouchStart = (e: TouchEvent): void => {
    isDragging = true;
    const t = e.touches[0];
    if (t) previewAt(t.clientX);
    e.preventDefault();
  };
  const onTouchMove = (e: TouchEvent): void => {
    if (!isDragging) return;
    const t = e.touches[0];
    if (t) previewAt(t.clientX);
    e.preventDefault();
  };
  const onTouchEnd = (e: TouchEvent): void => {
    if (!isDragging) return;
    isDragging = false;
    previewEnd?.();
    e.preventDefault();
    const t = e.changedTouches[0];
    if (t) commit(indexAt(t.clientX));
  };

  el.addEventListener("mousedown", onMouseDown);
  el.addEventListener("click", onClick);
  window.addEventListener("mousemove", onMouseMove);
  window.addEventListener("mouseup", onMouseUp);
  el.addEventListener("touchstart", onTouchStart, { passive: false });
  el.addEventListener("touchmove", onTouchMove, { passive: false });
  el.addEventListener("touchend", onTouchEnd, { passive: false });

  return () => {
    el.removeEventListener("mousedown", onMouseDown);
    el.removeEventListener("click", onClick);
    window.removeEventListener("mousemove", onMouseMove);
    window.removeEventListener("mouseup", onMouseUp);
    el.removeEventListener("touchstart", onTouchStart);
    el.removeEventListener("touchmove", onTouchMove);
    el.removeEventListener("touchend", onTouchEnd);
  };
}

export function fractionAt(el: HTMLElement, clientX: number): number {
  const rect = el.getBoundingClientRect();
  if (rect.width === 0) return 0;
  return Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
}
