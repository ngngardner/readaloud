import { defineHook } from "../lib/hook";
import { DOM_IDS, findElement, requireElement } from "../lib/dom_ids";
import { PersistedRecord } from "../lib/persisted_record";
import { attachScrubber, fractionAt } from "../lib/scrubber";
import { scrollFollow } from "../lib/scroll_follow";
import { readerSettings } from "../lib/reader_settings_store";
import { cycleOption } from "../lib/cycle_option";
import { type WordTiming, parseWordTimings, wordSelector } from "../lib/types";
import { attachWordMenu } from "./word_menu";

interface AudioPlayerDataset {
  audioUrl: string;
  timingsUrl: string;
  initialPosition?: string;
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
const SKIP_SECONDS = 10;
const AUTO_SCROLL_GRACE_MS = 800;

function coercePlayerPrefs(raw: unknown): Partial<PlayerPrefs> {
  if (!raw || typeof raw !== "object") return {};
  const r = raw as Record<string, unknown>;
  const out: { -readonly [K in keyof PlayerPrefs]?: PlayerPrefs[K] } = {};
  if (typeof r.speed === "number") out.speed = r.speed;
  if (typeof r.volume === "number") out.volume = r.volume;
  if (typeof r.collapsed === "boolean") out.collapsed = r.collapsed;
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

export const AudioPlayerHook = defineHook<HTMLDivElement, AudioPlayerDataset>(
  (ctx) => {
    const audio = requireElement(DOM_IDS.AUDIO_ELEMENT, HTMLAudioElement);
    const playPauseBtn = requireElement(DOM_IDS.PLAY_PAUSE_BTN, HTMLElement);
    const timeDisplay = findElement(DOM_IDS.TIME_DISPLAY, HTMLElement);
    const textContainer = findElement(DOM_IDS.CHAPTER_TEXT, HTMLElement);
    const resyncBtn = findElement(DOM_IDS.RESYNC_BTN, HTMLElement);
    const speedBadge = findElement(DOM_IDS.SPEED_BADGE, HTMLElement);

    if (!audio || !playPauseBtn) return;

    let timings: ReadonlyArray<WordTiming> = [];
    let currentWordIndex = -1;
    let lastReportedMs = -1;
    let rafId: number | undefined;
    let wordMenuCleanup: (() => void) | undefined;
    let intersectionObserver: IntersectionObserver | undefined;

    const applyAudioPrefs = (): void => {
      const p = playerPrefs.get();
      audio.playbackRate = p.speed;
      audio.volume = p.volume;
      updateSpeedBadge(p.speed);
    };

    const updateTimeDisplay = (): void => {
      if (!timeDisplay) return;
      timeDisplay.textContent = `${formatTime(audio.currentTime)} / ${formatTime(audio.duration)}`;
    };

    const updateSpeedBadge = (speed: number): void => {
      if (!speedBadge) return;
      speedBadge.textContent = speed === 1 ? "1x" : `${speed}x`;
    };

    const setSpeed = (speed: number): void => {
      playerPrefs.set({ speed });
      audio.playbackRate = speed;
      updateSpeedBadge(speed);
    };

    const cycleSpeed = (direction: "up" | "down"): void => {
      const closest = SPEEDS.reduce((best, s) =>
        Math.abs(s - audio.playbackRate) < Math.abs(best - audio.playbackRate)
          ? s
          : best,
      );
      setSpeed(cycleOption(SPEEDS, closest, direction));
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

    // Initial setup
    if (playerPrefs.get().collapsed) ctx.el.classList.add("collapsed");

    const volSlider = ctx.el.querySelector<HTMLInputElement>(
      "[data-volume-slider]",
    );
    if (volSlider) volSlider.value = String(playerPrefs.get().volume);
    updateSpeedBadge(playerPrefs.get().speed);

    // The <audio> element has phx-update="ignore" so it's preserved across
    // chapter switches (push_patch). Reassigning .src alone doesn't reliably
    // refetch on iOS Safari — call load() explicitly to invoke the resource
    // selection algorithm and reset the element's media state.
    audio.src = ctx.dataset.audioUrl;
    audio.load();
    applyAudioPrefs();

    ctx.on(audio, "loadedmetadata", () => {
      applyAudioPrefs();
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
        .then((data: unknown) => {
          timings = parseWordTimings(data);
          if (textContainer && !wordMenuCleanup)
            wordMenuCleanup = attachWordMenu(textContainer);
        })
        .catch((err: unknown) =>
          console.error("AudioPlayer: failed to load timings", err),
        );
    };
    fetchTimings(ctx.dataset.timingsUrl);

    // Restore initial position
    const initialMs = Number.parseInt(ctx.dataset.initialPosition ?? "0", 10);
    if (initialMs > 0) {
      ctx.on(
        audio,
        "loadedmetadata",
        () => {
          audio.currentTime = initialMs / 1000;
        },
        { once: true },
      );
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
      if (!ms || !ms.setPositionState) return;
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
        prefetchAbort.abort();
        prefetchAbort = null;
      }
      if (prefetchedBlobUrl) {
        URL.revokeObjectURL(prefetchedBlobUrl);
        prefetchedBlobUrl = null;
      }
      prefetchedFor = url;
      const abort = new AbortController();
      prefetchAbort = abort;
      fetch(url, { signal: abort.signal })
        .then((r) => {
          if (!r.ok) throw new Error(`HTTP ${r.status}`);
          return r.blob();
        })
        .then((blob) => {
          prefetchAbort = null;
          if (prefetchedFor !== url) return; // target changed mid-flight
          prefetchedBlobUrl = URL.createObjectURL(blob);
        })
        .catch((err: unknown) => {
          prefetchAbort = null;
          if ((err as Error)?.name !== "AbortError") {
            console.warn("AudioPlayer: next-chapter prefetch failed", err);
            // Reset prefetchedFor so we can retry later (e.g. on next
            // timeupdate) instead of being stuck thinking we're done.
            if (prefetchedFor === url) prefetchedFor = null;
          }
        });
    };

    // Swap to a different chapter without unmounting the player. Used by
    // both the auto-next-on-ended path and (if invoked from outside) by
    // server-pushed chapter changes. Critically: same <audio> element, so
    // the OS audio session is preserved and lock-screen playback continues
    // without requiring a new user gesture.
    const swapToChapter = (
      audioUrl: string,
      timingsUrl: string,
      chapterTitle: string,
    ): void => {
      audio.src = audioUrl;
      audio.load();
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
      audio.play().catch((err: unknown) => {
        console.warn("AudioPlayer: chapter-swap play blocked", err);
      });
    };

    const goToNextChapter = (): boolean => {
      const networkUrl = ctx.dataset.nextAudioUrl;
      const timingsUrl = ctx.dataset.nextTimingsUrl;
      const title = ctx.dataset.nextChapterTitle ?? "";
      if (!networkUrl || !timingsUrl) return false;

      // Use the prefetched in-memory blob if it's for THIS URL — this is
      // the whole point of prefetch and is what makes background-tab
      // autoplay actually work. Fall back to the network URL otherwise
      // (e.g. desktop user who never triggered prefetch).
      const useBlob =
        prefetchedBlobUrl !== null && prefetchedFor === networkUrl;
      const audioUrl = useBlob ? (prefetchedBlobUrl as string) : networkUrl;

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

      swapToChapter(audioUrl, timingsUrl, title);
      // Tell the server to push_patch the URL + reload chapter assigns.
      // Fire-and-forget: if the WebSocket is asleep (locked phone), the
      // event queues until reconnect — audio playback doesn't depend on it.
      ctx.pushEvent("next_chapter");
      return true;
    };

    const goToPrevChapter = (): boolean => {
      const url = ctx.dataset.prevAudioUrl;
      const timingsUrl = ctx.dataset.prevTimingsUrl;
      const title = ctx.dataset.prevChapterTitle ?? "";
      if (!url || !timingsUrl) return false;
      swapToChapter(url, timingsUrl, title);
      ctx.pushEvent("prev_chapter");
      return true;
    };

    if (ms) {
      updateMediaSessionMetadata();
      const safeSet = (
        action: MediaSessionAction,
        handler: MediaSessionActionHandler | null,
      ): void => {
        try {
          ms.setActionHandler(action, handler);
        } catch {
          // Browser may not support this action — fine, skip it.
        }
      };
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
      // Only register next/prev when there's actually a target; otherwise
      // the OS UI shows greyed-out buttons (or nothing) which is correct.
      if (ctx.dataset.nextAudioUrl) {
        safeSet("nexttrack", () => {
          goToNextChapter();
        });
      } else {
        safeSet("nexttrack", null);
      }
      if (ctx.dataset.prevAudioUrl) {
        safeSet("previoustrack", () => {
          goToPrevChapter();
        });
      } else {
        safeSet("previoustrack", null);
      }
      ctx.onDestroy(() => {
        // Clear handlers + metadata so a stale player on a different page
        // doesn't get media-key events meant for nothing.
        for (const a of [
          "play",
          "pause",
          "nexttrack",
          "previoustrack",
          "seekbackward",
          "seekforward",
          "seekto",
        ] as MediaSessionAction[]) {
          try {
            ms.setActionHandler(a, null);
          } catch {}
        }
        ms.metadata = null;
      });
    }

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
        const isCollapsed = ctx.el.classList.toggle("collapsed");
        playerPrefs.set({ collapsed: isCollapsed });
      });
    }

    if (volSlider) {
      ctx.on(volSlider, "input", () => {
        const vol = Number.parseFloat(volSlider.value);
        audio.volume = vol;
        playerPrefs.set({ volume: vol });
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
        ctx.pushEvent("audio_position", { position_ms: nowMs });
      }
    });

    // Play/pause state — drives scrollFollow + button icon + position report
    ctx.on(audio, "play", () => {
      playPauseBtn.innerHTML = "&#10074;&#10074;";
      scrollFollow.setPlaying(true);
      startHighlightLoop();
      if (ms) ms.playbackState = "playing";
      updateMediaSessionPosition();
    });
    ctx.on(audio, "pause", () => {
      playPauseBtn.innerHTML = "&#9654;";
      scrollFollow.setPlaying(false);
      stopHighlightLoop();
      if (ms) ms.playbackState = "paused";
      ctx.pushEvent("audio_position", {
        position_ms: Math.round(audio.currentTime * 1000),
      });
    });
    ctx.on(audio, "ended", () => {
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

    const unsubScroll = scrollFollow.subscribe((s) => {
      if (!resyncBtn) return;
      if (s.autoScrollPaused) resyncBtn.classList.remove("hidden");
      else resyncBtn.classList.add("hidden");
    });
    ctx.onDestroy(unsubScroll);

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

    // Final cleanup not covered by ctx.on
    ctx.onDestroy(() => {
      stopHighlightLoop();
      audio.pause();
      wordMenuCleanup?.();
      if (prefetchAbort) prefetchAbort.abort();
      if (prefetchedBlobUrl) URL.revokeObjectURL(prefetchedBlobUrl);
      if (currentBlobUrl) URL.revokeObjectURL(currentBlobUrl);
    });
  },
);
