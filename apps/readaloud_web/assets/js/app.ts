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
