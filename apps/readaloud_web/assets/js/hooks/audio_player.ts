import { cycleOption } from "../lib/cycle_option";
import { DOM_IDS, findElement, requireElement } from "../lib/dom_ids";
import type { PlayerEventDetailValue } from "../lib/events";
import { defineHook } from "../lib/hook";
import { watchNavAck } from "../lib/nav_ack";
import { PersistedRecord } from "../lib/persisted_record";
import { attachPlayerEventBuffer } from "../lib/player_event_buffer";
import {
  attachProgressBuffer,
  type ProgressBuffer,
  readLastPosition,
  writeLastPosition,
} from "../lib/progress_buffer";
import { readerSettings } from "../lib/reader_settings_store";
import { scrollFollow } from "../lib/scroll_follow";
import { attachScrubber, fractionAt } from "../lib/scrubber";
import {
  isJsonObject,
  type JsonValue,
  parseWordTimings,
  type WordTiming,
  wordSelector,
} from "../lib/types";
import { attachWordMenu } from "./word_menu";

interface AudioPlayerDataset {
  audioUrl: string;
  timingsUrl: string;
  initialPosition?: string;
  bookId?: string;
  bookTitle?: string;
  chapterTitle?: string;
  chapterId?: string;
  nextChapterId?: string;
  nextAudioUrl?: string;
  nextTimingsUrl?: string;
  nextChapterTitle?: string;
  prevChapterId?: string;
  prevAudioUrl?: string;
  prevTimingsUrl?: string;
  prevChapterTitle?: string;
}

interface PlayerPrefs {
  readonly speed: number;
  readonly volume: number;
  readonly collapsed: boolean;
}

const PLAYER_PREFS_DEFAULTS: PlayerPrefs = Object.freeze({
  speed: 1,
  volume: 1,
  collapsed: false,
});

const PLAYER_PREFS_KEY = "readaloud-player-prefs";

const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2] as const;

const POSITION_REPORT_INTERVAL_MS = 5000;
// Diagnostic heartbeat cadence while playing. Each heartbeat carries the
// wall-clock and audio-position deltas since the previous one — on a
// healthy player they match (scaled by playbackRate); divergence or a gap
// in the series is direct evidence of background throttling/suspension.
const HEARTBEAT_INTERVAL_MS = 30_000;
const SKIP_SECONDS = 10;
const AUTO_SCROLL_GRACE_MS = 800;

// Play/pause button glyphs. The LV template renders ▶ (as &#9654;) as the
// static default; the hook overwrites textContent on every audio play/pause.
const PLAY_GLYPH = "▶";
const PAUSE_GLYPH = "❚❚";

function coercePlayerPrefs(raw: JsonValue): Partial<PlayerPrefs> {
  if (!isJsonObject(raw)) return {};
  const out: { -readonly [K in keyof PlayerPrefs]?: PlayerPrefs[K] } = {};
  if (typeof raw.speed === "number") out.speed = raw.speed;
  if (typeof raw.volume === "number") out.volume = raw.volume;
  if (typeof raw.collapsed === "boolean") out.collapsed = raw.collapsed;
  return out;
}

function migrateLegacyPlayerPrefs(): void {
  if (localStorage.getItem(PLAYER_PREFS_KEY) !== null) return;
  const legacySpeed = localStorage.getItem("readaloud-playback-speed");
  const legacyVolume = localStorage.getItem("readaloud-volume");
  const legacyCollapsed = localStorage.getItem("readaloud-player-collapsed");
  if (legacySpeed === null && legacyVolume === null && legacyCollapsed === null)
    return;
  const migrated: PlayerPrefs = {
    speed:
      legacySpeed !== null
        ? Number.parseFloat(legacySpeed)
        : PLAYER_PREFS_DEFAULTS.speed,
    volume:
      legacyVolume !== null
        ? Number.parseFloat(legacyVolume)
        : PLAYER_PREFS_DEFAULTS.volume,
    collapsed: legacyCollapsed === "true",
  };
  localStorage.setItem(PLAYER_PREFS_KEY, JSON.stringify(migrated));
}

migrateLegacyPlayerPrefs();
const playerPrefs = new PersistedRecord<PlayerPrefs>(
  PLAYER_PREFS_KEY,
  PLAYER_PREFS_DEFAULTS,
  coercePlayerPrefs,
);

function findActiveWord(
  timings: ReadonlyArray<WordTiming>,
  ms: number,
): number {
  let idx = -1;
  let lo = 0;
  let hi = timings.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >>> 1;
    const t = timings[mid];
    if (!t) break;
    if (ms >= t.startMs && ms < t.endMs) {
      idx = mid;
      break;
    } else if (ms < t.startMs) {
      hi = mid - 1;
    } else {
      idx = mid;
      lo = mid + 1;
    }
  }
  if (idx >= 0 && idx < timings.length - 1) {
    const next = timings[idx + 1];
    if (next && ms >= next.startMs) idx += 1;
  }
  return idx;
}

function formatTime(secs: number): string {
  if (!Number.isFinite(secs) || secs < 0) return "0:00";
  const m = Math.floor(secs / 60);
  const s = Math.floor(secs % 60);
  return `${m}:${s < 10 ? "0" : ""}${s}`;
}

// Monotonically increasing player-instance ID. Each hook mount gets one;
// shows up in every log line so we can tell apart pre-/post-remount
// instances when reading the browser console after the fact.
let nextPlayerId = 1;

// Which chapter's audio is actually loaded into a given <audio> element.
// This is the client's canonical "what is playing" — every src write goes
// through swapToChapter/set-initial-src, which record it here, and every
// reconciliation compares against it. A WeakMap at module scope (not hook
// state, not a DOM attribute) because it must match the element's own
// lifetime: the element survives LV remounts via phx-update="ignore"
// while hook state dies with the instance, and morphdom strips runtime
// DOM attributes even on ignored elements.
const LOADED_CHAPTER = new WeakMap<HTMLAudioElement, string>();

// How long the client-side last-position cache outranks the server's
// initial position after a reload. Within this window the local cache is
// fresher than any beacon that may still be racing the page load; beyond
// it (other device, next-day resume) the server row is the authority.
const LAST_POSITION_TRUST_MS = 10 * 60_000;

export const AudioPlayerHook = defineHook<HTMLDivElement, AudioPlayerDataset>(
  (ctx) => {
    const audio = requireElement(DOM_IDS.AUDIO_ELEMENT, HTMLAudioElement);
    const playPauseBtn = requireElement(DOM_IDS.PLAY_PAUSE_BTN, HTMLElement);
    const timeDisplay = findElement(DOM_IDS.TIME_DISPLAY, HTMLElement);
    const textContainer = findElement(DOM_IDS.CHAPTER_TEXT, HTMLElement);
    const resyncBtn = findElement(DOM_IDS.RESYNC_BTN, HTMLElement);
    const speedBadge = findElement(DOM_IDS.SPEED_BADGE, HTMLElement);

    if (!audio || !playPauseBtn) return;

    const playerId = nextPlayerId++;

    // `data-book-id` is set by the LV template and is part of the hook's
    // contract — if it's ever missing or unparseable, that's a template
    // bug and we want to fail loudly at mount, not silently no-op every
    // observation downstream.
    const bookId = Number.parseInt(ctx.dataset.bookId ?? "", 10);
    if (!Number.isFinite(bookId)) {
      throw new Error(
        "AudioPlayerHook: data-book-id is missing or unparseable",
      );
    }

    // Durable diagnostic-event buffer. Every log() call below lands here
    // too, giving the server (→ journald → Loki + Prometheus) the same
    // event stream the browser console gets — that's what lets us debug
    // background-playback weirdness on a phone after the fact, without
    // the phone attached to a devtools session.
    const events = attachPlayerEventBuffer({
      bookId,
      beaconUrl: `/api/books/${bookId}/player-events`,
      pushEvents: (batch) => {
        ctx.pushEvent("player_events", { events: batch });
      },
    });
    ctx.onDestroy(() => events.detach());

    // Detailed always-on logging for autoplay debugging. When the user
    // reports a symptom ("phone woke up at 11:07 and audio was at 0:00")
    // these lines + the chapter/book ids let us line up the JS-side state
    // machine with server logs (see reader_live.ex Logger.info calls).
    type LogValue = string | number | boolean | null | undefined;
    const log = (event: string, extra?: Record<string, LogValue>): void => {
      const wall = new Date().toISOString();
      const t =
        typeof performance !== "undefined"
          ? Math.round(performance.now())
          : Date.now();
      const base: Record<string, LogValue> = {
        player: playerId,
        chapter: ctx.dataset.chapterId,
        t,
      };
      if (extra) Object.assign(base, extra);
      // Always-on autoplay telemetry per the comment above; this is
      // intentional production logging, not debug residue.
      // ast-grep-ignore: no-console-log
      console.log(`[autoplay ${wall}] ${event}`, base);

      // Mirror to the server-side diagnostic channel. `undefined` values
      // are dropped (they don't survive JSON anyway).
      const detail: Record<string, PlayerEventDetailValue> = {
        player: playerId,
      };
      if (extra) {
        for (const [key, value] of Object.entries(extra)) {
          if (value !== undefined) detail[key] = value;
        }
      }
      const fields: {
        chapter_id?: string;
        position_ms?: number;
        detail?: Record<string, PlayerEventDetailValue>;
      } = { position_ms: Math.round(audio.currentTime * 1000), detail };
      const chapterId = ctx.dataset.chapterId;
      if (chapterId !== undefined) fields.chapter_id = chapterId;
      events.record(event, fields);
    };

    let timings: ReadonlyArray<WordTiming> = [];
    let currentWordIndex = -1;
    let lastReportedMs = -1;
    // Heartbeat state; wall=0 means "no previous beat" (start of playback,
    // or invalidated by pause/seek so deltas never span a discontinuity).
    let lastHeartbeatWall = 0;
    let lastHeartbeatPosMs = 0;
    let rafId: number | undefined;
    let wordMenuCleanup: (() => void) | undefined;
    let intersectionObserver: IntersectionObserver | undefined;

    // Durable position-observation buffer. The hook owns the lifetime;
    // localStorage owns the cross-mount state (so a buffered observation
    // from before a LV remount or page-hide drains on the next mount).
    const progress: ProgressBuffer = attachProgressBuffer({
      bookId,
      beaconUrl: `/api/books/${bookId}/progress`,
      pushObservations: (observations) => {
        ctx.pushEvent("progress_observations", { observations });
      },
    });
    ctx.onDestroy(() => progress.detach());

    const updateTimeDisplay = (): void => {
      if (!timeDisplay) return;
      timeDisplay.textContent = `${formatTime(audio.currentTime)} / ${formatTime(audio.duration)}`;
    };

    const updateSpeedBadge = (speed: number): void => {
      if (!speedBadge) return;
      speedBadge.textContent = speed === 1 ? "1x" : `${speed}x`;
    };

    const cycleSpeed = (direction: "up" | "down"): void => {
      const closest = SPEEDS.reduce((best, s) =>
        Math.abs(s - audio.playbackRate) < Math.abs(best - audio.playbackRate)
          ? s
          : best,
      );
      playerPrefs.set({ speed: cycleOption(SPEEDS, closest, direction) });
    };

    const togglePlayback = (): void => {
      if (audio.paused) audio.play();
      else audio.pause();
    };

    const seekToWordIndex = (idx: number): void => {
      const t = timings[idx];
      if (!t) return;
      audio.currentTime = t.startMs / 1000;
      if (audio.paused) audio.play();
    };

    // Word highlighting with auto-scroll
    const highlightWord = (ms: number): void => {
      if (!textContainer || timings.length === 0) return;
      const idx = findActiveWord(timings, ms);
      if (idx === currentWordIndex) return;

      if (currentWordIndex >= 0) {
        const old = textContainer.querySelector<HTMLElement>(
          wordSelector(currentWordIndex),
        );
        old?.classList.remove("word-active");
        old?.classList.add("word-spoken");
      }

      if (idx >= 0) {
        const next = textContainer.querySelector<HTMLElement>(
          wordSelector(idx),
        );
        if (next) {
          next.classList.add("word-active");
          next.classList.remove("word-spoken");

          if (!scrollFollow.get().autoScrollPaused) {
            scrollFollow.beginAutoScroll(AUTO_SCROLL_GRACE_MS);
            next.scrollIntoView({ behavior: "smooth", block: "center" });
            if (intersectionObserver) {
              intersectionObserver.disconnect();
              intersectionObserver.observe(next);
            }
          }
        }
      }

      if (idx > currentWordIndex) {
        for (let i = Math.max(0, currentWordIndex); i < idx; i++) {
          const el = textContainer.querySelector<HTMLElement>(wordSelector(i));
          if (el) {
            el.classList.remove("word-active");
            el.classList.add("word-spoken");
          }
        }
      } else if (idx >= 0 && idx < currentWordIndex) {
        for (let i = idx + 1; i <= currentWordIndex; i++) {
          const el = textContainer.querySelector<HTMLElement>(wordSelector(i));
          if (el) el.classList.remove("word-spoken", "word-active");
        }
      }

      currentWordIndex = idx;
    };

    const startHighlightLoop = (): void => {
      const tick = (): void => {
        if (!audio.paused) {
          highlightWord(audio.currentTime * 1000);
          rafId = requestAnimationFrame(tick);
        }
      };
      rafId = requestAnimationFrame(tick);
    };

    const stopHighlightLoop = (): void => {
      if (rafId !== undefined) {
        cancelAnimationFrame(rafId);
        rafId = undefined;
      }
    };

    const volSlider = ctx.el.querySelector<HTMLInputElement>(
      "[data-volume-slider]",
    );

    // Player prefs → DOM. Bound to the store so chapter-swap re-renders can't
    // desync the slider, the speed badge, or the collapsed class from the
    // user's actual preference. The audio element's playbackRate/volume are
    // also re-applied here; src changes can reset playbackRate, so the
    // loadedmetadata handler below re-runs apply for that case.
    const applyPlayerPrefs = (p: Readonly<PlayerPrefs>): void => {
      audio.playbackRate = p.speed;
      audio.volume = p.volume;
      updateSpeedBadge(p.speed);
      if (volSlider) volSlider.value = String(p.volume);
      ctx.el.classList.toggle("collapsed", p.collapsed);
    };
    ctx.bindStore(playerPrefs, applyPlayerPrefs);

    // The <audio> element has phx-update="ignore" so it's preserved across
    // chapter switches (push_patch) AND across LV reconnect/re-mount. The
    // hook itself, however, is destroyed and re-mounted on a re-mount —
    // so on mount we may find an <audio> element that's already loaded
    // (and possibly mid-playback) from a previous hook instance. In that
    // case we MUST NOT touch its src — doing so would interrupt the
    // user's listening session, which is exactly the bug we're chasing
    // with sleeping-mobile autoplay (LV WebSocket times out → re-mount on
    // wake → forced reload → 00:00/00:00).
    //
    // Heuristic: only set src if the element doesn't have one yet (or
    // has the page URL, the default for an unset <audio>). If it has
    // any other src — network URL, or a `blob:` URL prefetched by a
    // previous hook instance — leave it alone.
    const wantSrc = ctx.dataset.audioUrl;
    const existingSrc = audio.src;
    const hasMeaningfulSrc =
      existingSrc !== "" &&
      existingSrc !== window.location.href &&
      existingSrc !== `${window.location.origin}/`;
    log("mount", {
      hasMeaningfulSrc,
      existingSrcKind: existingSrc.startsWith("blob:")
        ? "blob"
        : existingSrc === "" || existingSrc === window.location.href
          ? "empty"
          : "url",
      audioPaused: audio.paused,
      audioCurrentTime: audio.currentTime,
      audioReadyState: audio.readyState,
      autoNextChapter: readerSettings.get().autoNextChapter,
      hasNext: !!ctx.dataset.nextAudioUrl,
      hasPrev: !!ctx.dataset.prevAudioUrl,
      bookTitle: ctx.dataset.bookTitle,
      chapterTitle: ctx.dataset.chapterTitle,
    });
    if (!hasMeaningfulSrc) {
      log("set-initial-src");
      audio.src = wantSrc;
      audio.load();
      if (ctx.dataset.chapterId) {
        LOADED_CHAPTER.set(audio, ctx.dataset.chapterId);
      }
    } else {
      log("preserve-existing-src");
      // A preserved src was set by a previous hook instance, which also
      // recorded its chapter in LOADED_CHAPTER (module scope survives
      // remounts). The fallback only covers a same-page hook crash.
      if (!LOADED_CHAPTER.has(audio) && ctx.dataset.chapterId) {
        LOADED_CHAPTER.set(audio, ctx.dataset.chapterId);
      }
    }

    ctx.on(audio, "loadedmetadata", () => {
      applyPlayerPrefs(playerPrefs.get());
      updateTimeDisplay();
      updateMediaSessionPosition();
    });
    ctx.on(audio, "durationchange", updateTimeDisplay);

    // Word timings — fetched on mount and re-fetched whenever we swap to a
    // new chapter via swapToChapter().
    const fetchTimings = (url: string): void => {
      timings = [];
      currentWordIndex = -1;
      fetch(url)
        .then((r) => r.json())
        .then((data: JsonValue) => {
          timings = parseWordTimings(data);
          if (textContainer && !wordMenuCleanup)
            wordMenuCleanup = attachWordMenu(textContainer);
        })
        .catch((err: Error) =>
          console.error("AudioPlayer: failed to load timings", err),
        );
    };
    fetchTimings(ctx.dataset.timingsUrl);

    // Restore initial position — only on a fresh load. On re-mount of an
    // already-playing element we'd otherwise rewind the user back to a
    // saved position from a different LV session.
    //
    // The server's initial position competes with the client-side
    // last-position cache: after a reload, the beacon carrying the final
    // observations may still be in flight when the new page renders, so
    // the server value can be seconds stale (the 2026-06-11 incident
    // restarted a chapter at 0:00 that the client knew was at 5.8s).
    // Same chapter + recent → take whichever is further along.
    const serverMs = Number.parseInt(ctx.dataset.initialPosition ?? "0", 10);
    if (!hasMeaningfulSrc) {
      const last = readLastPosition(bookId);
      const lastTrusted =
        last !== null &&
        last.chapter_id === ctx.dataset.chapterId &&
        Date.now() - last.at_ms < LAST_POSITION_TRUST_MS;
      const restoreMs =
        lastTrusted && last.position_ms > serverMs
          ? last.position_ms
          : serverMs;
      if (restoreMs > 0) {
        log("restore-position", {
          ms: restoreMs,
          serverMs,
          source: restoreMs === serverMs ? "server" : "client-cache",
        });
        ctx.on(
          audio,
          "loadedmetadata",
          () => {
            audio.currentTime = restoreMs / 1000;
          },
          { once: true },
        );
      }
    }

    // --- Media Session API ----------------------------------------------
    // Registers the OS-level lock-screen / notification controls. Without
    // this, a sleeping mobile device has no native "next chapter" button
    // and the WebSocket-bound LV nav often fails when the device wakes.
    // With this, the OS gives us a working next/prev button even when JS
    // is throttled, and the audio session keeps the lock screen UI alive
    // across chapter swaps (since we reuse the same <audio> element).
    const ms =
      typeof navigator !== "undefined" && "mediaSession" in navigator
        ? navigator.mediaSession
        : null;

    const updateMediaSessionMetadata = (): void => {
      if (!ms) return;
      ms.metadata = new MediaMetadata({
        title: ctx.dataset.chapterTitle ?? "",
        artist: ctx.dataset.bookTitle ?? "",
        album: ctx.dataset.bookTitle ?? "",
      });
    };

    const updateMediaSessionPosition = (): void => {
      if (!ms?.setPositionState) return;
      if (!Number.isFinite(audio.duration) || audio.duration <= 0) return;
      try {
        ms.setPositionState({
          duration: audio.duration,
          position: Math.min(audio.currentTime, audio.duration),
          playbackRate: audio.playbackRate || 1,
        });
      } catch {
        // Some browsers throw on invalid positions; ignore.
      }
    };

    // --- Next-chapter prefetch -----------------------------------------
    // Mobile browsers (iOS Safari especially) suspend network fetches
    // when the screen locks. If we wait until `ended` to fetch the next
    // chapter's audio, the request stalls and audio.play() never gets a
    // valid resource — exactly the bug we're chasing. So while the
    // current chapter is still playing (and the device presumably
    // awake), download the next chapter's audio fully into a Blob URL.
    // On `ended` we swap to the in-memory blob — no network needed.
    let currentBlobUrl: string | null = null; // points to in-use audio.src
    let prefetchedBlobUrl: string | null = null;
    let prefetchedFor: string | null = null;
    let prefetchAbort: AbortController | null = null;

    const tryStartPrefetch = (): void => {
      if (!readerSettings.get().autoNextChapter) return;
      const url = ctx.dataset.nextAudioUrl;
      if (!url) return;
      // Already done or in flight for the same URL? Skip.
      if (prefetchedBlobUrl && prefetchedFor === url) return;
      if (prefetchAbort && prefetchedFor === url) return;
      // Target URL changed (e.g. user manually jumped chapters) — drop
      // any in-flight or stale-blob state and restart.
      if (prefetchAbort) {
        log("prefetch-abort-stale", { for: prefetchedFor });
        prefetchAbort.abort();
        prefetchAbort = null;
      }
      if (prefetchedBlobUrl) {
        log("prefetch-revoke-stale", { for: prefetchedFor });
        URL.revokeObjectURL(prefetchedBlobUrl);
        prefetchedBlobUrl = null;
      }
      prefetchedFor = url;
      const abort = new AbortController();
      prefetchAbort = abort;
      log("prefetch-start", { url });
      const startedAt = performance.now();
      fetch(url, { signal: abort.signal })
        .then((r) => {
          if (!r.ok) throw new Error(`HTTP ${r.status}`);
          return r.blob();
        })
        .then((blob) => {
          prefetchAbort = null;
          if (prefetchedFor !== url) {
            log("prefetch-discard-target-changed", {
              completedFor: url,
              currentTarget: prefetchedFor,
            });
            return;
          }
          prefetchedBlobUrl = URL.createObjectURL(blob);
          log("prefetch-done", {
            url,
            bytes: blob.size,
            durationMs: Math.round(performance.now() - startedAt),
          });
        })
        .catch((err: Error) => {
          prefetchAbort = null;
          if (err.name !== "AbortError") {
            log("prefetch-fail", { url, error: String(err) });
            console.warn("AudioPlayer: next-chapter prefetch failed", err);
            // Reset prefetchedFor so we can retry later (e.g. on next
            // timeupdate) instead of being stuck thinking we're done.
            if (prefetchedFor === url) prefetchedFor = null;
          } else {
            log("prefetch-aborted", { url });
          }
        });
    };

    // Swap to a different chapter without unmounting the player. The ONLY
    // writer of audio.src after mount — both the user-initiated nav
    // projection (clientNavigate) and the server-driven reconciler
    // (syncAudioToDataset) go through here, so the loaded-chapter record
    // and the last-position cache can't drift from the element. Critically:
    // same <audio> element, so the OS audio session is preserved and
    // lock-screen playback continues without requiring a new user gesture.
    const swapToChapter = (
      chapterId: string,
      audioUrl: string,
      timingsUrl: string,
      chapterTitle: string,
      opts: { autoplay: boolean },
    ): void => {
      log("swap-to-chapter", {
        srcKind: audioUrl.startsWith("blob:") ? "blob" : "url",
        chapterTitle,
        audioPaused: audio.paused,
        autoplay: opts.autoplay,
      });
      audio.src = audioUrl;
      audio.load();
      LOADED_CHAPTER.set(audio, chapterId);
      // Keep the client-side position cache coherent with the swap: the
      // new chapter starts at 0 no matter which path triggered it.
      writeLastPosition(bookId, chapterId, 0);
      // Update title eagerly so the lock screen shows the new chapter name
      // even before the LV push_patch round-trip lands.
      if (ms) {
        ms.metadata = new MediaMetadata({
          title: chapterTitle,
          artist: ctx.dataset.bookTitle ?? "",
          album: ctx.dataset.bookTitle ?? "",
        });
      }
      fetchTimings(timingsUrl);
      if (opts.autoplay) {
        audio
          .play()
          .then(() => log("swap-play-ok"))
          .catch((err: Error) => {
            log("swap-play-blocked", { error: String(err) });
            console.warn("AudioPlayer: chapter-swap play blocked", err);
          });
      }
    };

    // Build a /books/:bookId/read/:chapterId?nav=internal URL by swapping
    // the chapter id in the current pathname. The current path always
    // matches /books/:bookId/read/:N (we're rendering the reader LV), so
    // a regex replace is enough — no need to thread book_id through the
    // hook's dataset. Returns null if the pathname isn't on the reader.
    const buildReaderUrl = (chapterId: string): string | null => {
      const path = window.location.pathname;
      if (!/\/books\/\d+\/read\/\d+/.test(path)) return null;
      return `${path.replace(/\/read\/\d+/, `/read/${chapterId}`)}?nav=internal`;
    };

    // Adjacent-chapter nav target from the dataset. Returns null when the
    // neighbor has no audio yet — callers fall back to the server-owned
    // path so the user can still reach audio-less chapters.
    const navTarget = (
      dir: "next" | "prev",
    ): {
      chapterId: string;
      networkUrl: string;
      timingsUrl: string;
      title: string;
    } | null => {
      const d = ctx.dataset;
      const chapterId = dir === "next" ? d.nextChapterId : d.prevChapterId;
      const networkUrl = dir === "next" ? d.nextAudioUrl : d.prevAudioUrl;
      const timingsUrl = dir === "next" ? d.nextTimingsUrl : d.prevTimingsUrl;
      const title =
        (dir === "next" ? d.nextChapterTitle : d.prevChapterTitle) ?? "";
      if (!chapterId || !networkUrl || !timingsUrl) return null;
      return { chapterId, networkUrl, timingsUrl, title };
    };

    // The single user-initiated chapter-change projection. Every client
    // writer (pill buttons, keyboard arrows, lock-screen media keys,
    // auto-next on ended) lands here, and the chapter transition fans out
    // to every replica in one place: audio.src (+ MediaSession title +
    // timings) via swapToChapter, the URL via pushState, persistence via
    // the durable progress buffer, and the server's assigns via an acked
    // pushEvent. No writer updates a subset.
    const clientNavigate = (dir: "next" | "prev"): boolean => {
      const navEvent = dir === "next" ? "next_chapter" : "prev_chapter";
      const target = navTarget(dir);
      if (!target) {
        log(`${dir}-chapter-blocked-no-target`);
        return false;
      }

      // Use the prefetched in-memory blob if it's for THIS URL — this is
      // the whole point of prefetch and is what makes background-tab
      // autoplay actually work. Fall back to the network URL otherwise
      // (prev nav, or a desktop user who never triggered prefetch).
      const audioUrl =
        prefetchedBlobUrl !== null && prefetchedFor === target.networkUrl
          ? prefetchedBlobUrl
          : target.networkUrl;
      const useBlob = audioUrl !== target.networkUrl;
      log(dir === "next" ? "go-to-next-chapter" : "go-to-prev-chapter", {
        useBlob,
        prefetchedFor,
        prefetchInFlight: prefetchAbort !== null,
        toTitle: target.title,
      });

      // The blob currently in use as audio.src (if any) is being replaced
      // — revoke it so we don't leak ~tens of MB per chapter swap.
      if (currentBlobUrl) URL.revokeObjectURL(currentBlobUrl);
      currentBlobUrl = useBlob ? audioUrl : null;
      // Detach the prefetched-blob slot since it's now the current one
      // (or we didn't use it). Either way, the next prefetch (for the
      // chapter after this) starts fresh.
      prefetchedBlobUrl = null;
      prefetchedFor = null;
      if (prefetchAbort) {
        prefetchAbort.abort();
        prefetchAbort = null;
      }

      swapToChapter(
        target.chapterId,
        audioUrl,
        target.timingsUrl,
        target.title,
        {
          autoplay: true,
        },
      );

      // Update browser URL client-side BEFORE notifying the server. This
      // is the critical fix for sleeping-mobile autoplay: server-side
      // push_patch only updates the URL when its diff reaches the
      // client, which doesn't happen if the WebSocket is suspended (and
      // the LV process times out before delivery). With this pushState
      // the URL stays in sync with audio.src regardless of WS state, so
      // a refresh after wake lands on the chapter that's actually
      // playing — not the previous one.
      const newUrl = buildReaderUrl(target.chapterId);
      if (newUrl) {
        history.pushState({}, "", newUrl);
        log("history-pushstate", { url: newUrl });
      }

      // Persist the pivot through the durable buffer. If the WS is
      // suspended (mobile lock — the original autoplay-stranding bug),
      // the buffer falls back to sendBeacon on visibilitychange:hidden
      // so the new chapter / 0:00 reset survives even with a dead WS.
      // `pivot: true` lets the server's assign-reconciler treat this as
      // an authoritative chapter change (position ticks never reconcile).
      progress.observe({
        chapter_id: target.chapterId,
        audio_position_ms: 0,
        scroll_position: 0,
        pivot: true,
      });

      // Tell the server to reload chapter assigns. `client_owned: true`
      // means JS owns BOTH the URL update (already pushState'd above)
      // AND the persistence write (already buffered above), so the
      // server skips its own push_patch and observe! — pushing twice
      // would create a duplicate history entry, and observing twice
      // would race with the buffered drain.
      //
      // The ack watchdog covers the wedged-socket case: a socket that's
      // open but not delivering buffers this push silently, leaving the
      // reader text on the old chapter while audio + URL + persistence
      // have all advanced. No ack while visible → force a reconnect,
      // which remounts the LV from the pushState'd URL.
      log("push-event", { event: navEvent });
      watchNavAck({
        push: (onAck) =>
          ctx.pushEventAck(
            navEvent,
            // Absolute target, not "advance from current": if the pivot
            // observation above reaches the server first, the reconciler
            // has already moved assigns to the target — a relative
            // advance would then double-step past it.
            { client_owned: true, chapter_id: target.chapterId },
            onAck,
          ),
        onTimeout: () => {
          log("nav-ack-timeout", { event: navEvent });
          ctx.dispatch("readaloud:force-reconnect");
        },
      });
      return true;
    };

    const goToNextChapter = (): boolean => clientNavigate("next");
    const goToPrevChapter = (): boolean => clientNavigate("prev");

    const safeSet = (
      action: MediaSessionAction,
      handler: MediaSessionActionHandler | null,
    ): void => {
      if (!ms) return;
      try {
        ms.setActionHandler(action, handler);
      } catch {
        // Browser may not support this action — fine, skip it.
      }
    };

    // Bound at mount and re-bound on every LV update: the dataset's
    // next/prev targets change with the chapter, so a handler set for a
    // neighbor that no longer exists — or missing for one that now does —
    // leaves the OS lock-screen buttons stale. Only register when there's
    // actually a target; otherwise the OS shows greyed-out buttons (or
    // nothing), which is correct.
    const registerMediaSessionNavHandlers = (): void => {
      if (!ms) return;
      if (ctx.dataset.nextAudioUrl) {
        safeSet("nexttrack", () => {
          log("media-session-nexttrack");
          goToNextChapter();
        });
      } else {
        safeSet("nexttrack", null);
      }
      if (ctx.dataset.prevAudioUrl) {
        safeSet("previoustrack", () => {
          log("media-session-previoustrack");
          goToPrevChapter();
        });
      } else {
        safeSet("previoustrack", null);
      }
    };

    if (ms) {
      updateMediaSessionMetadata();
      safeSet("play", () => {
        audio.play().catch(() => {});
      });
      safeSet("pause", () => audio.pause());
      safeSet("seekbackward", (details) => {
        const delta = details.seekOffset ?? SKIP_SECONDS;
        audio.currentTime = Math.max(0, audio.currentTime - delta);
      });
      safeSet("seekforward", (details) => {
        const delta = details.seekOffset ?? SKIP_SECONDS;
        const max = Number.isFinite(audio.duration)
          ? audio.duration
          : Number.POSITIVE_INFINITY;
        audio.currentTime = Math.min(max, audio.currentTime + delta);
      });
      safeSet("seekto", (details) => {
        if (typeof details.seekTime === "number") {
          audio.currentTime = details.seekTime;
        }
      });
      registerMediaSessionNavHandlers();
      ctx.onDestroy(() => {
        // Clear handlers + metadata so a stale player on a different page
        // doesn't get media-key events meant for nothing.
        const actions: readonly MediaSessionAction[] = [
          "play",
          "pause",
          "nexttrack",
          "previoustrack",
          "seekbackward",
          "seekforward",
          "seekto",
        ];
        for (const a of actions) {
          try {
            ms.setActionHandler(a, null);
          } catch {}
        }
        ms.metadata = null;
      });
    }

    // --- Reconciler: audio follows the server-rendered chapter ----------
    // Every server-owned navigation (chapter-bar jump, browser
    // back/forward, conflict-modal jump, any future writer) reaches the
    // browser as a morphdom patch of this hook's dataset. Watching for the
    // dataset's chapter to *transition* and re-aligning the <audio> element
    // covers all of them in one place — no per-writer audio handling, which
    // is how the chapter-bar jump shipped without one.
    //
    // Transition-triggered (not raw inequality) on purpose: right after a
    // client-owned nav, LOADED_CHAPTER is already on the new chapter while
    // the dataset still shows the old one until the server's diff lands. An
    // unrelated diff arriving in that window must not "fix" the audio
    // backwards. A dataset transition means the server moved the chapter;
    // the LOADED_CHAPTER check then skips the no-op case where the client
    // itself initiated that move.
    let lastSeenDatasetChapter = ctx.dataset.chapterId;
    const syncAudioToDataset = (): void => {
      const want = ctx.dataset.chapterId;
      if (!want || want === lastSeenDatasetChapter) return;
      lastSeenDatasetChapter = want;
      if (LOADED_CHAPTER.get(audio) === want) return;
      // Server-driven moves preserve the user's play/pause state instead
      // of force-playing: jumping chapters while paused should stay paused.
      const wasPlaying = !audio.paused;
      log("sync-audio-to-dataset", { resume: wasPlaying });
      swapToChapter(
        want,
        ctx.dataset.audioUrl,
        ctx.dataset.timingsUrl,
        ctx.dataset.chapterTitle ?? "",
        { autoplay: wasPlaying },
      );
    };
    ctx.onUpdate(() => {
      syncAudioToDataset();
      // Chapter changes move the next/prev targets and the lock-screen
      // title with them.
      registerMediaSessionNavHandlers();
      updateMediaSessionMetadata();
    });

    // Controls
    ctx.on(playPauseBtn, "click", togglePlayback);

    const skipBack = ctx.el.querySelector<HTMLElement>("[data-skip-back]");
    const skipFwd = ctx.el.querySelector<HTMLElement>("[data-skip-forward]");
    if (skipBack) {
      ctx.on(skipBack, "click", () => {
        audio.currentTime = Math.max(0, audio.currentTime - SKIP_SECONDS);
      });
    }
    if (skipFwd) {
      ctx.on(skipFwd, "click", () => {
        const max = Number.isFinite(audio.duration)
          ? audio.duration
          : Number.POSITIVE_INFINITY;
        audio.currentTime = Math.min(max, audio.currentTime + SKIP_SECONDS);
      });
    }

    const collapseToggle = ctx.el.querySelector<HTMLElement>(
      "[data-collapse-toggle]",
    );
    if (collapseToggle) {
      ctx.on(collapseToggle, "click", () => {
        playerPrefs.set({ collapsed: !playerPrefs.get().collapsed });
      });
    }

    if (volSlider) {
      ctx.on(volSlider, "input", () => {
        playerPrefs.set({ volume: Number.parseFloat(volSlider.value) });
      });
    }

    // Scrubbers (main + mini)
    const scrubMain = ctx.el.querySelector<HTMLElement>("[data-scrubber]");
    const scrubMini = ctx.el.querySelector<HTMLElement>("[data-scrubber-mini]");
    const seekToFraction = (f: number): void => {
      if (Number.isFinite(audio.duration))
        audio.currentTime = f * audio.duration;
    };
    for (const sc of [scrubMain, scrubMini]) {
      if (!sc) continue;
      const dispose = attachScrubber<number>({
        el: sc,
        indexAt: (clientX) => fractionAt(sc, clientX),
        preview: () => {},
        commit: seekToFraction,
      });
      ctx.onDestroy(dispose);
    }

    // Time updates: progress bars + time display + position report.
    // Also kicks off the next-chapter prefetch once the user has clearly
    // committed to this chapter (>15% through). Doing it here, gated on
    // playback progress, means we don't waste bandwidth on chapters the
    // user opens and immediately abandons.
    const PREFETCH_TRIGGER_FRACTION = 0.15;
    ctx.on(audio, "timeupdate", () => {
      if (!audio.duration) return;
      const pct = (audio.currentTime / audio.duration) * 100;
      const fill = ctx.el.querySelector<HTMLElement>("[data-progress-fill]");
      if (fill) fill.style.width = `${pct}%`;
      const fillMini = ctx.el.querySelector<HTMLElement>(
        "[data-progress-fill-mini]",
      );
      if (fillMini) fillMini.style.width = `${pct}%`;
      updateTimeDisplay();

      if (audio.currentTime / audio.duration > PREFETCH_TRIGGER_FRACTION) {
        tryStartPrefetch();
      }

      const nowMs = Math.round(audio.currentTime * 1000);
      if (
        lastReportedMs < 0 ||
        Math.abs(nowMs - lastReportedMs) >= POSITION_REPORT_INTERVAL_MS
      ) {
        lastReportedMs = nowMs;
        // Attribute the position to the chapter the audio has actually
        // loaded, not the dataset: while a nav's server round-trip is in
        // flight (or wedged) the dataset lags the audio, and pairing the
        // old chapter id with the new chapter's position corrupts
        // progress.
        const chapterId = LOADED_CHAPTER.get(audio) ?? ctx.dataset.chapterId;
        if (chapterId) {
          progress.observe({
            chapter_id: chapterId,
            audio_position_ms: nowMs,
          });
        }
      }

      const wallNow = Date.now();
      if (
        !audio.paused &&
        wallNow - lastHeartbeatWall >= HEARTBEAT_INTERVAL_MS
      ) {
        log(
          "heartbeat",
          lastHeartbeatWall > 0
            ? {
                wallDeltaMs: wallNow - lastHeartbeatWall,
                audioDeltaMs: nowMs - lastHeartbeatPosMs,
                rate: audio.playbackRate,
              }
            : { rate: audio.playbackRate },
        );
        lastHeartbeatWall = wallNow;
        lastHeartbeatPosMs = nowMs;

        // Cheap replica-consistency assertion, piggybacked on the
        // heartbeat: the loaded audio, the LV-rendered chapter, and the
        // URL should all agree. A mismatch is the state-whackamole bug
        // class showing itself — the event lands in Prometheus (via the
        // PlayerEvents whitelist) so divergence is an alert with context
        // instead of a user report.
        const urlChapter =
          window.location.pathname.match(/\/read\/(\d+)/)?.[1] ?? null;
        const loadedChapter = LOADED_CHAPTER.get(audio) ?? null;
        const datasetChapter = ctx.dataset.chapterId ?? null;
        if (
          loadedChapter !== null &&
          (loadedChapter !== datasetChapter ||
            (urlChapter !== null && loadedChapter !== urlChapter))
        ) {
          log("state-divergence", {
            loaded: loadedChapter,
            dataset: datasetChapter,
            url: urlChapter,
          });
        }
      }
    });

    // Play/pause icon — bound to the audio element's own state so it stays
    // in sync across morphdom patches (chapter swap re-renders #audio-player
    // and would otherwise reset the button text to the template default).
    ctx.bindElement(audio, ["play", "pause"], () => {
      playPauseBtn.textContent = audio.paused ? PLAY_GLYPH : PAUSE_GLYPH;
    });

    // Side effects on play/pause that aren't DOM projection.
    ctx.on(audio, "play", () => {
      // Fresh heartbeat series — deltas must not span the paused gap.
      lastHeartbeatWall = 0;
      log("audio-play", {
        currentTime: audio.currentTime,
        duration: audio.duration,
      });
      scrollFollow.setPlaying(true);
      startHighlightLoop();
      if (ms) ms.playbackState = "playing";
      updateMediaSessionPosition();
    });
    ctx.on(audio, "pause", () => {
      log("audio-pause", {
        currentTime: audio.currentTime,
        duration: audio.duration,
        atEnd:
          Number.isFinite(audio.duration) &&
          audio.duration > 0 &&
          audio.currentTime >= audio.duration - 0.5,
      });
      scrollFollow.setPlaying(false);
      stopHighlightLoop();
      if (ms) ms.playbackState = "paused";
      // Same loaded-chapter attribution rationale as the timeupdate path.
      const chapterId = LOADED_CHAPTER.get(audio) ?? ctx.dataset.chapterId;
      if (chapterId) {
        progress.observe({
          chapter_id: chapterId,
          audio_position_ms: Math.round(audio.currentTime * 1000),
        });
      }
    });
    ctx.on(audio, "ended", () => {
      log("audio-ended", {
        autoNext: readerSettings.get().autoNextChapter,
        hasPrefetchedBlob: prefetchedBlobUrl !== null,
        prefetchInFlight: prefetchAbort !== null,
        prefetchedFor,
        nextUrl: ctx.dataset.nextAudioUrl ?? null,
      });
      stopHighlightLoop();
      if (readerSettings.get().autoNextChapter) {
        // JS-side chapter swap on the same <audio> element. This is the
        // critical path for sleeping-mobile autoplay: a full LV navigation
        // would tear down the OS audio session and silently fail when the
        // device is locked. Same-element src swap keeps the lock-screen
        // controls live and the audio session uninterrupted.
        goToNextChapter();
      }
    });
    ctx.on(audio, "error", () => {
      const err = audio.error;
      log("audio-error", {
        code: err?.code ?? null,
        message: err?.message ?? null,
        currentSrc: audio.currentSrc?.startsWith("blob:") ? "blob" : "url",
      });
    });
    ctx.on(audio, "stalled", () =>
      log("audio-stalled", { currentTime: audio.currentTime }),
    );
    ctx.on(audio, "waiting", () =>
      log("audio-waiting", { currentTime: audio.currentTime }),
    );
    ctx.on(audio, "loadedmetadata", () =>
      log("audio-loadedmetadata", { duration: audio.duration }),
    );
    ctx.on(audio, "seeked", () => {
      // A seek invalidates heartbeat deltas; restart the series.
      lastHeartbeatWall = 0;
      log("audio-seeked", { currentTime: audio.currentTime });
    });

    // --- Background-state diagnostics ---------------------------------
    // The "weird state on mobile" reports all hinge on transitions the
    // console can't show us after the fact: screen lock / app switch
    // (visibilitychange), bfcache traversal (pageshow/pagehide), tab
    // freezing (freeze/resume — Page Lifecycle API, not in TS's event
    // maps, hence the manual listeners), and network loss. Snapshot the
    // <audio> element at every transition so the server-side trace shows
    // exactly what state playback was in when the platform intervened.
    const audioSnapshot = (): Record<string, LogValue> => ({
      paused: audio.paused,
      currentTime: Math.round(audio.currentTime * 100) / 100,
      readyState: audio.readyState,
      networkState: audio.networkState,
      srcKind: audio.currentSrc.startsWith("blob:") ? "blob" : "url",
    });

    const onVisibilityChange = (): void => {
      log(
        document.visibilityState === "hidden"
          ? "visibility-hidden"
          : "visibility-visible",
        audioSnapshot(),
      );
    };
    document.addEventListener("visibilitychange", onVisibilityChange);
    ctx.onDestroy(() =>
      document.removeEventListener("visibilitychange", onVisibilityChange),
    );

    const onFreeze = (): void => log("page-freeze", audioSnapshot());
    const onResume = (): void => log("page-resume", audioSnapshot());
    document.addEventListener("freeze", onFreeze);
    document.addEventListener("resume", onResume);
    ctx.onDestroy(() => {
      document.removeEventListener("freeze", onFreeze);
      document.removeEventListener("resume", onResume);
    });

    ctx.on(window, "pagehide", (e) =>
      log("page-hide", { persisted: e.persisted, ...audioSnapshot() }),
    );
    ctx.on(window, "pageshow", (e) =>
      log("page-show", { persisted: e.persisted, ...audioSnapshot() }),
    );
    ctx.on(window, "online", () => log("net-online", audioSnapshot()));
    ctx.on(window, "offline", () => log("net-offline", audioSnapshot()));

    // Mirror the app.ts reload guard's decisions into this channel:
    // "deferred" = LV wanted to hard-reload the page while background
    // audio was playing and we stopped it; "resumed" = the page came
    // back to visibility with a healthy socket so no reload was needed.
    ctx.on(window, "readaloud:lv-reload-deferred", () =>
      log("lv-reload-deferred", audioSnapshot()),
    );
    ctx.on(window, "readaloud:lv-reload-resumed", () =>
      log("lv-reload-resumed", audioSnapshot()),
    );
    // Mirror wedged-socket recoveries the same way — whichever hook's
    // nav-ack watchdog triggered it (this one or the chapter bar's).
    ctx.on(window, "readaloud:force-reconnect", () =>
      log("force-reconnect", audioSnapshot()),
    );

    // Re-sync UX
    if (resyncBtn) {
      ctx.on(resyncBtn, "click", () => {
        scrollFollow.resume();
        if (currentWordIndex >= 0 && textContainer) {
          const el = textContainer.querySelector<HTMLElement>(
            wordSelector(currentWordIndex),
          );
          el?.scrollIntoView({ behavior: "smooth", block: "center" });
        }
      });
    }

    if (textContainer && "IntersectionObserver" in window) {
      intersectionObserver = new IntersectionObserver(
        (entries) => {
          for (const entry of entries) {
            if (entry.isIntersecting && scrollFollow.get().autoScrollPaused) {
              scrollFollow.resume();
            }
          }
        },
        { threshold: 0.5 },
      );
      ctx.onDestroy(() => intersectionObserver?.disconnect());
    }

    ctx.bindStore(scrollFollow, (s) => {
      if (!resyncBtn) return;
      resyncBtn.classList.toggle("hidden", !s.autoScrollPaused);
    });

    // Word menu actions
    ctx.on(window, "word-action", (detail) => {
      if (detail.kind === "play") seekToWordIndex(detail.index);
    });

    // Speed badge cycle
    if (speedBadge) ctx.on(speedBadge, "click", () => cycleSpeed("up"));

    // Keyboard-shortcut events
    ctx.on(window, "audio:toggle-playback", togglePlayback);
    ctx.on(window, "audio:toggle-mute", () => {
      audio.muted = !audio.muted;
    });
    ctx.on(window, "audio:change-speed", ({ direction }) =>
      cycleSpeed(direction),
    );

    // Manual chapter nav (floating-pill buttons + keyboard arrows). These
    // dispatch a window event instead of phx-click="next_chapter" while
    // the audio player is mounted so we can do a same-<audio>-element src
    // swap instead of letting the server's push_patch leave us playing
    // the previous chapter. When the next/prev chapter has no audio yet,
    // goTo*Chapter returns false and we fall back to the server-owned
    // path so the user can still navigate to audio-less chapters.
    ctx.on(window, "audio:nav-next-chapter", () => {
      log("nav-next-chapter-event");
      if (!goToNextChapter()) ctx.pushEvent("next_chapter", {});
    });
    ctx.on(window, "audio:nav-prev-chapter", () => {
      log("nav-prev-chapter-event");
      if (!goToPrevChapter()) ctx.pushEvent("prev_chapter", {});
    });

    // Final cleanup not covered by ctx.on. Important: do NOT pause the
    // audio or revoke its current blob URL here. Destroy fires on LV
    // reconnect/re-mount (long phone sleep → server LV process times out
    // → client re-mount on wake) — and the <audio> element survives
    // (phx-update="ignore"). Pausing or revoking would interrupt the
    // user's listening session at exactly the moment they wake the phone
    // hoping playback continues. If the player is genuinely going away
    // (user navigates off the reader), the <audio> element gets removed
    // from the DOM, which auto-pauses it — no explicit pause needed.
    //
    // We do still abort and revoke the *prefetch* slot: that blob is not
    // tied to the playing audio element, so leaking it across re-mount
    // would just waste memory.
    ctx.onDestroy(() => {
      log("destroy", {
        audioPaused: audio.paused,
        currentTime: audio.currentTime,
        duration: audio.duration,
        prefetchInFlight: prefetchAbort !== null,
        hasPrefetchedBlob: prefetchedBlobUrl !== null,
      });
      stopHighlightLoop();
      wordMenuCleanup?.();
      if (prefetchAbort) prefetchAbort.abort();
      if (prefetchedBlobUrl) URL.revokeObjectURL(prefetchedBlobUrl);
    });
  },
);
