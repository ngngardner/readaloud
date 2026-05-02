type Listener = (state: ScrollFollowState) => void;

export interface ScrollFollowState {
  readonly playing: boolean;
  readonly autoScrollPaused: boolean;
  readonly inAutoScroll: boolean;
}

class ScrollFollowController {
  private state: ScrollFollowState = Object.freeze({
    playing: false,
    autoScrollPaused: false,
    inAutoScroll: false,
  });
  private readonly listeners = new Set<Listener>();
  private autoScrollEndTimer: number | undefined;

  get(): ScrollFollowState {
    return this.state;
  }

  subscribe(fn: Listener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  setPlaying(playing: boolean): void {
    this.update({ playing });
  }

  beginAutoScroll(graceMs = 800): void {
    this.update({ inAutoScroll: true });
    if (this.autoScrollEndTimer !== undefined)
      clearTimeout(this.autoScrollEndTimer);
    this.autoScrollEndTimer = window.setTimeout(() => {
      this.update({ inAutoScroll: false });
      this.autoScrollEndTimer = undefined;
    }, graceMs);
  }

  manualScroll(): void {
    if (!this.state.playing || this.state.inAutoScroll) return;
    if (this.state.autoScrollPaused) return;
    this.update({ autoScrollPaused: true });
  }

  resume(): void {
    if (!this.state.autoScrollPaused) return;
    this.update({ autoScrollPaused: false });
  }

  private update(patch: Partial<ScrollFollowState>): void {
    const next = Object.freeze({ ...this.state, ...patch });
    if (
      next.playing === this.state.playing &&
      next.autoScrollPaused === this.state.autoScrollPaused &&
      next.inAutoScroll === this.state.inAutoScroll
    ) {
      return;
    }
    this.state = next;
    for (const fn of this.listeners) fn(next);
  }
}

export const scrollFollow = new ScrollFollowController();
