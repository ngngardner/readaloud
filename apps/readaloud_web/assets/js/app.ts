import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/readaloud_web";
import topbar from "../vendor/topbar";

import { ScrollTrackerHook } from "./hooks/scroll_tracker";
import { AudioPlayerHook } from "./hooks/audio_player";
import { ThemeHook } from "./hooks/theme";
import { SidebarHook } from "./hooks/sidebar";
import { DragDropHook } from "./hooks/drag_drop";
import { FloatingPillHook } from "./hooks/floating_pill";
import {
  ReaderSettingsControlsHook,
  ReaderStylesHook,
} from "./hooks/reader_settings";
import { KeyboardShortcutsHook } from "./hooks/keyboard_shortcuts";
import { ChapterBarHook } from "./hooks/chapter_bar";
import { LibrarySortHook } from "./hooks/library_sort";

import type { LiveReloader } from "./lib/events";

const Hooks = {
  ...colocatedHooks,
  ScrollTrackerHook,
  AudioPlayerHook,
  ThemeHook,
  SidebarHook,
  DragDropHook,
  FloatingPillHook,
  ReaderStylesHook,
  ReaderSettingsControlsHook,
  KeyboardShortcutsHook,
  ChapterBarHook,
  LibrarySortHook,
};

const csrfTokenMeta = document.querySelector<HTMLMetaElement>(
  "meta[name='csrf-token']",
);
const csrfToken = csrfTokenMeta?.getAttribute("content") ?? "";

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

// --- Background-audio reload guard -----------------------------------
// Every socket-recovery failure path in phoenix_live_view converges on
// LiveSocket.reloadWithJitter → window.location.reload(): a hook
// pushEvent whose reply times out (PUSH_TIMEOUT=30s), a main-view join
// error, and the close-code-1000 failsafe. On a locked phone that
// recovery is fatal to playback: the OS suspends the tab's network
// while the <audio> element keeps playing, so the channel is a zombie —
// the hook's own pushes (next_chapter, progress, player events) time
// out, and LV "recovers" by reloading the page, destroying the playing
// blob audio and the autoplay gesture with it. That is the 2026-06-10
// incident reconstructed in the [player] log channel: swap-play-ok at
// 13:24:27, destroy (audioPaused=false) at 13:25:31, fresh mount paused
// at 0:00, silence.
//
// Guard: while the page is hidden AND the reader audio is actively
// playing, defer any reload until the page is visible again. On
// visibility, give the socket a grace window to reconnect on its own
// (the normal rejoin path — hooks remount, the <audio> element survives
// via phx-update="ignore", buffers drain); only fall through to the
// real reload if it's still down. Re-entering the wrapper from the
// grace timer re-evaluates the conditions, so audio that resumed
// hidden-playback mid-grace defers again instead of dying.
//
// reloadWithJitter is private API (phoenix_live_view 1.1.x); the shape
// is pinned by e2e/tests/audio-reload-guard.test.js, which drives it
// directly.
const RELOAD_RECONNECT_GRACE_MS = 4000;
type ReloadWithJitter = (view: object, log?: () => void) => void;
// reloadWithJitter/isConnected are real LiveSocket members that
// phoenix_live_view's .d.ts doesn't expose — a cast is the only way
// through; the e2e reload-guard test pins the runtime shape.
// ast-grep-ignore: no-as-cast, no-unknown-type
const reloadable = liveSocket as unknown as {
  reloadWithJitter: ReloadWithJitter;
  isConnected(): boolean;
};
const originalReload = reloadable.reloadWithJitter.bind(liveSocket);
let reloadDeferred = false;

reloadable.reloadWithJitter = (view, log) => {
  const audio = document.getElementById("audio-element");
  const backgroundAudioLive =
    document.visibilityState === "hidden" &&
    audio instanceof HTMLAudioElement &&
    !audio.paused;
  if (!backgroundAudioLive) {
    originalReload(view, log);
    return;
  }
  if (reloadDeferred) return;
  reloadDeferred = true;
  window.dispatchEvent(new CustomEvent("readaloud:lv-reload-deferred"));
  const onVisible = (): void => {
    if (document.visibilityState !== "visible") return;
    document.removeEventListener("visibilitychange", onVisible);
    window.setTimeout(() => {
      reloadDeferred = false;
      if (reloadable.isConnected()) {
        window.dispatchEvent(new CustomEvent("readaloud:lv-reload-resumed"));
      } else {
        reloadable.reloadWithJitter(view, log);
      }
    }, RELOAD_RECONNECT_GRACE_MS);
  };
  document.addEventListener("visibilitychange", onVisible);
};

// --- Client-owned URL changes must reach LiveView's View.href ---------
// Every (re)join sends View.href as the `url` param the server mounts
// from. LV updates it only on its own paths (delivered push_patch, link
// patch); a raw history.pushState from the audio player leaves it at the
// page-load URL. Client-owned chapter navs deliberately skip push_patch,
// so without this bridge a socket rejoin — Android kills the WS on every
// screen-off — re-mounts the page-load chapter, the hook's dataset
// transitions backwards and syncAudioToDataset yanks the audio back to
// a chapter that already finished (2026-08-18 commute incident).
// `main.setHref` is a public View method that phoenix_live_view's own
// typings don't declare, hence the local shape.
// ast-grep-ignore: no-as-cast, no-unknown-type
const hrefable = liveSocket as unknown as {
  main?: { setHref(href: string): void };
};
window.addEventListener("readaloud:client-pushstate", (e: Event) => {
  if (!(e instanceof CustomEvent)) return;
  const detail: { url?: string } | null = e.detail;
  if (typeof detail?.url === "string") hrefable.main?.setHref(detail.url);
});

// --- Wedged-socket recovery -------------------------------------------
// The nav-ack watchdog (lib/nav_ack.ts) fires this when a chapter-nav
// pushEvent gets no channel ack while the page is visible: the socket is
// open-but-not-delivering, so the reader text can't follow the audio.
// A disconnect/connect cycle tears the zombie channel down and remounts
// the LV from View.href — kept current by the bridge above — so the
// remount lands on the chapter that's actually playing. The <audio>
// element survives (phx-update="ignore" + the hook's
// preserve-existing-src mount path), so playback continues.
window.addEventListener("readaloud:force-reconnect", () => {
  liveSocket.disconnect();
  liveSocket.connect();
});

topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", () => topbar.show(300));
window.addEventListener("phx:page-loading-stop", () => topbar.hide());

liveSocket.connect();

declare global {
  interface Window {
    liveSocket: LiveSocket;
    liveReloader?: LiveReloader;
  }
  interface WindowEventMap {
    "phx:live_reload:attached": CustomEvent<LiveReloader>;
  }
}
window.liveSocket = liveSocket;

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", (e) => {
    const reloader = e.detail;
    reloader.enableServerLogs();

    let keyDown: string | null = null;
    window.addEventListener("keydown", (ev) => {
      keyDown = ev.key;
    });
    window.addEventListener("keyup", () => {
      keyDown = null;
    });
    window.addEventListener(
      "click",
      (ev) => {
        if (keyDown === "c") {
          ev.preventDefault();
          ev.stopImmediatePropagation();
          reloader.openEditorAtCaller(ev.target);
        } else if (keyDown === "d") {
          ev.preventDefault();
          ev.stopImmediatePropagation();
          reloader.openEditorAtDef(ev.target);
        }
      },
      true,
    );

    window.liveReloader = reloader;
  });
}
