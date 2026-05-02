import type { LiveViewHookSpec, ViewHookInternal } from "phoenix_live_view";
import type {
  ReadaloudHandleEvents,
  ReadaloudPushEvents,
  ReadaloudWindowEvents,
} from "./events";

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
}

const READALOUD_EVENT_PREFIX_RE =
  /^(audio:|manual-scroll$|auto-scroll-|word-action$|toggle-pill$|chapter-bar-close$|phx:)/;

function isReadaloudEvent(event: string): boolean {
  return READALOUD_EVENT_PREFIX_RE.test(event);
}

export function defineHook<
  TEl extends HTMLElement = HTMLElement,
  TDataset = Record<string, string | undefined>,
>(setup: (ctx: HookContext<TEl, TDataset>) => void): LiveViewHookSpec {
  return {
    mounted(this: ViewHookInternal): void {
      const disposers: Array<() => void> = [];
      const lv = this;

      const ctx: HookContext<TEl, TDataset> = {
        el: this.el as TEl,
        dataset: this.el.dataset as unknown as Readonly<TDataset>,

        on(
          target: EventTarget,
          event: string,
          handler: (arg: unknown) => void,
          opts?: AddEventListenerOptions,
        ): void {
          if (target === window && isReadaloudEvent(event)) {
            const wrapped = (e: Event): void => {
              const detail = (e as CustomEvent).detail;
              handler(detail);
            };
            window.addEventListener(event, wrapped);
            disposers.push(() => window.removeEventListener(event, wrapped));
          } else {
            target.addEventListener(event, handler as EventListener, opts);
            disposers.push(() =>
              target.removeEventListener(event, handler as EventListener, opts),
            );
          }
        },

        dispatch(event: string, detail?: unknown): void {
          window.dispatchEvent(new CustomEvent(event, { detail }));
        },

        pushEvent(event: string, payload?: object): void {
          lv.pushEvent(event, payload ?? {});
        },

        handleEvent(event: string, handler: (payload: never) => void): void {
          const ref = lv.handleEvent(event, handler as (p: unknown) => void);
          disposers.push(() => lv.removeHandleEvent(ref));
        },

        onDestroy(fn: () => void): void {
          disposers.push(fn);
        },
      };

      (this as unknown as { _ctxDisposers: Array<() => void> })._ctxDisposers =
        disposers;

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

    destroyed(this: ViewHookInternal): void {
      const disposers = (
        this as unknown as { _ctxDisposers?: Array<() => void> }
      )._ctxDisposers;
      if (!disposers) return;
      for (const dispose of disposers) {
        try {
          dispose();
        } catch (err) {
          console.error("hook disposer threw:", err);
        }
      }
    },
  };
}
