// A subscribable readable. Anything matching this shape can be wired into
// a hook's DOM via ctx.bindStore. PersistedRecord, scrollFollow, and any
// future client-side state container should implement it.
//
// Lives here (not in lib/hook.ts) so the hook framework and the concrete
// stores both depend on it, rather than the stores depending on the hook
// framework.
export interface ReadableStore<T> {
  get(): T;
  subscribe(fn: (snapshot: T) => void): () => void;
}

// Shared listener registry for ReadableStore implementations. Catches
// listener exceptions so one bad subscriber can't starve the others —
// without this, a throw in a hook's apply function leaves later hooks
// permanently desynced from store state.
export class Notifier<T> {
  private readonly listeners = new Set<(snapshot: T) => void>();

  subscribe(fn: (snapshot: T) => void): () => void {
    this.listeners.add(fn);
    return () => {
      this.listeners.delete(fn);
    };
  }

  notify(snapshot: T): void {
    for (const fn of this.listeners) {
      try {
        fn(snapshot);
      } catch (err) {
        console.error("store listener threw:", err);
      }
    }
  }
}
