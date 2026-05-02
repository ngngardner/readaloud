declare module "phoenix" {
  export class Socket {
    constructor(endpoint: string, opts?: Record<string, unknown>);
  }
}

declare module "phoenix_html" {}

declare module "phoenix_live_view" {
  import type { Socket } from "phoenix";

  export interface ViewHookInternal {
    el: HTMLElement;
    pushEvent(
      event: string,
      payload?: object,
      onReply?: (reply: unknown, ref: number) => void,
    ): void;
    pushEventTo(
      target: string | HTMLElement,
      event: string,
      payload?: object,
      onReply?: (reply: unknown, ref: number) => void,
    ): void;
    handleEvent(event: string, callback: (payload: unknown) => void): unknown;
    removeHandleEvent(ref: unknown): void;
    upload(name: string, files: File[]): unknown;
    uploadTo(
      target: string | HTMLElement,
      name: string,
      files: File[],
    ): unknown;
  }

  export interface LiveViewHookSpec {
    mounted?(this: ViewHookInternal): void;
    beforeUpdate?(this: ViewHookInternal): void;
    updated?(this: ViewHookInternal): void;
    destroyed?(this: ViewHookInternal): void;
    disconnected?(this: ViewHookInternal): void;
    reconnected?(this: ViewHookInternal): void;
  }

  export interface LiveSocketOpts {
    longPollFallbackMs?: number;
    params?: Record<string, unknown> | (() => Record<string, unknown>);
    hooks?: Record<string, LiveViewHookSpec>;
  }

  export class LiveSocket {
    constructor(endpoint: string, socket: typeof Socket, opts: LiveSocketOpts);
    connect(): void;
    enableDebug(): void;
    disableDebug(): void;
    enableLatencySim(ms: number): void;
    disableLatencySim(): void;
  }
}

declare module "phoenix-colocated/readaloud_web" {
  import type { LiveViewHookSpec } from "phoenix_live_view";
  export const hooks: Record<string, LiveViewHookSpec>;
}

declare const process: {
  env: {
    NODE_ENV?: string;
  };
};
