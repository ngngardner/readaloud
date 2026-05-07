import type { LiveViewHookSpec, ViewHookInternal } from "phoenix_live_view";
import type {
  ReadaloudHandleEvents,
  ReadaloudPushEvents,
  ReadaloudWindowEvents,
} from "./events";
import type { ReadableStore } from "./store";

type EmptyPayload = undefined | Record<string, never>;

type WindowEventDetail<K extends keyof ReadaloudWindowEvents> =
  ReadaloudWindowEvents[K] extends undefined
    ? []
    : [detail: ReadaloudWindowEvents[K]];

type PushEventArgs<K extends keyof ReadaloudPushEvents> =
  ReadaloudPushEvents[K] extends EmptyPayload
    ? []
    : [payload: ReadaloudPushEvents[K]];

export interface HookContext<
  TEl extends HTMLElement = HTMLElement,
  TDataset = Record<string, string | undefined>,
> {
  readonly el: TEl;
  readonly dataset: Readonly<TDataset>;

  on<K extends keyof HTMLElementEventMap>(
    target: HTMLElement | Document,
    event: K,
    handler: (e: HTMLElementEventMap[K]) => void,
    opts?: AddEventListenerOptions,
  ): void;
  on<K extends keyof WindowEventMap>(
    target: Window,
    event: K,
    handler: (e: WindowEventMap[K]) => void,
    opts?: AddEventListenerOptions,
  ): void;
  on<K extends keyof ReadaloudWindowEvents>(
    target: Window,
    event: K,
    handler: ReadaloudWindowEvents[K] extends undefined
      ? () => void
      : (detail: ReadaloudWindowEvents[K]) => void,
  ): void;

  dispatch<K extends keyof ReadaloudWindowEvents>(
    event: K,
    ...detail: WindowEventDetail<K>
  ): void;

  pushEvent<K extends keyof ReadaloudPushEvents>(
    event: K,
    ...payload: PushEventArgs<K>
  ): void;

  handleEvent<K extends keyof ReadaloudHandleEvents>(
    event: K,
    handler: (payload: ReadaloudHandleEvents[K]) => void,
  ): void;

  onDestroy(fn: () => void): void;
  onUpdate(fn: () => void): void;

  // Bind a DOM projection to a subscribable store. Runs apply once with the
  // current snapshot, re-runs on every store change, and re-runs on every
  // LiveView update so morphdom can't desync the DOM from the truth.
  bindStore<T>(store: ReadableStore<T>, apply: (snapshot: T) => void): void;

  // Bind a DOM projection to one or more events on an element. Runs apply
  // once now, then on every listed event, then on every LiveView update.
  // Use when the source of truth lives on the element itself (e.g. an
  // <audio>'s paused state) rather than in a store.
  //
  // K is constrained to keyof HTMLElementEventMap rather than something
  // narrower per element-subtype because TypeScript's lib.dom.d.ts puts
  // every media event on every HTMLElement via GlobalEventHandlersEventMap
  // (the legacy `onplay`/`onpause` mixin). Tightening this further would
  // require shadowing lib.dom.d.ts — not worth it. Misuse fails silently
  // (DOM no-ops on a wrong-target listener); we accept this trade-off.
  bindElement<K extends keyof HTMLElementEventMap>(
    target: HTMLElement,
    events: readonly K[],
    apply: () => void,
  ): void;
}

const READALOUD_EVENT_PREFIX_RE =
  /^(audio:|manual-scroll$|auto-scroll-|word-action$|toggle-pill$|chapter-bar-close$|readaloud:|phx:)/;

function isReadaloudEvent(event: string): boolean {
  return READALOUD_EVENT_PREFIX_RE.test(event);
}

interface HookState {
  readonly disposers: Array<() => void>;
  readonly updateHandlers: Array<() => void>;
}

// Per-mount state, keyed off the LV view-hook `this`. WeakMap avoids
// bolting expando fields onto ViewHookInternal (which would force a cast
// at every read site to satisfy TS).
const HOOK_STATE = new WeakMap<ViewHookInternal, HookState>();

export function defineHook<
  TEl extends HTMLElement = HTMLElement,
  TDataset = Record<string, string | undefined>,
>(setup: (ctx: HookContext<TEl, TDataset>) => void): LiveViewHookSpec {
  return {
    mounted(this: ViewHookInternal): void {
      const disposers: Array<() => void> = [];
      const updateHandlers: Array<() => void> = [];
      const lv = this;

      const ctx: HookContext<TEl, TDataset> = {
        // The LV markup is the source of truth for the element subtype and
        // the dataset shape. TS can't verify this contract; the caller of
        // defineHook<TEl, TDataset> asserts it.
        // ast-grep-ignore: no-as-cast
        el: this.el as TEl,
        // ast-grep-ignore
        dataset: this.el.dataset as unknown as Readonly<TDataset>,

        on(
          target: EventTarget,
          event: string,
          // Impl signature for the typed overloads above. Callers see the
          // narrowed handler types; the impl must accept the union, which
          // TS only expresses as `unknown`.
          // ast-grep-ignore: no-unknown-type
          handler: (arg: unknown) => void,
          opts?: AddEventListenerOptions,
        ): void {
          if (target === window && isReadaloudEvent(event)) {
            const wrapped = (e: Event): void => {
              if (e instanceof CustomEvent) handler(e.detail);
            };
            window.addEventListener(event, wrapped);
            disposers.push(() => window.removeEventListener(event, wrapped));
          } else {
            // The DOM API only knows EventListener, not our typed overloads.
            // ast-grep-ignore: no-as-cast
            target.addEventListener(event, handler as EventListener, opts);
            disposers.push(() =>
              // ast-grep-ignore: no-as-cast
              target.removeEventListener(event, handler as EventListener, opts),
            );
          }
        },

        // ast-grep-ignore: no-unknown-type
        dispatch(event: string, detail?: unknown): void {
          window.dispatchEvent(new CustomEvent(event, { detail }));
        },

        pushEvent(event: string, payload?: object): void {
          lv.pushEvent(event, payload ?? {});
        },

        handleEvent(event: string, handler: (payload: never) => void): void {
          // Phoenix's typed shim wants `(payload: unknown) => void`. Our
          // public overload above narrows the payload per event K; the
          // impl signature uses `never` for parametric assignability and
          // we re-widen here to satisfy the LV type.
          // ast-grep-ignore
          const ref = lv.handleEvent(event, handler as (p: unknown) => void);
          disposers.push(() => lv.removeHandleEvent(ref));
        },

        onDestroy(fn: () => void): void {
          disposers.push(fn);
        },

        onUpdate(fn: () => void): void {
          updateHandlers.push(fn);
        },

        bindStore<T>(
          store: ReadableStore<T>,
          apply: (snapshot: T) => void,
        ): void {
          apply(store.get());
          disposers.push(store.subscribe(apply));
          updateHandlers.push(() => apply(store.get()));
        },

        bindElement<K extends keyof HTMLElementEventMap>(
          target: HTMLElement,
          events: readonly K[],
          apply: () => void,
        ): void {
          apply();
          for (const ev of events) {
            target.addEventListener(ev, apply);
            disposers.push(() => target.removeEventListener(ev, apply));
          }
          updateHandlers.push(apply);
        },
      };

      HOOK_STATE.set(this, { disposers, updateHandlers });

      try {
        setup(ctx);
      } catch (err) {
        for (const dispose of disposers) {
          try {
            dispose();
          } catch {}
        }
        throw err;
      }
    },

    updated(this: ViewHookInternal): void {
      const state = HOOK_STATE.get(this);
      if (!state) return;
      for (const fn of state.updateHandlers) {
        try {
          fn();
        } catch (err) {
          console.error("hook update handler threw:", err);
        }
      }
    },

    destroyed(this: ViewHookInternal): void {
      const state = HOOK_STATE.get(this);
      if (!state) return;
      for (const dispose of state.disposers) {
        try {
          dispose();
        } catch (err) {
          console.error("hook disposer threw:", err);
        }
      }
      HOOK_STATE.delete(this);
    },
  };
}
