import { defineHook } from "../lib/hook";
import { PersistedRecord } from "../lib/persisted_record";
import { attachScrubber, fractionAt } from "../lib/scrubber";
import { scrollFollow } from "../lib/scroll_follow";
import { readerSettings } from "../lib/reader_settings_store";
import { cycleOption } from "../lib/cycle_option";
import { type WordTiming, parseWordTimings } from "../lib/types";
import { attachWordMenu } from "./word_menu";

interface AudioPlayerDataset {
  audioUrl: string;
  timingsUrl: string;
  initialPosition?: string;
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
    const audio = document.getElementById("audio-element");
    const playPauseBtn = document.getElementById("play-pause-btn");
    const timeDisplay = document.getElementById("time-display");
    const textContainer = document.getElementById("chapter-text");
    const resyncBtn = document.getElementById("resync-btn");
    const speedBadge = document.getElementById("speed-badge");

    if (!(audio instanceof HTMLAudioElement) || !playPauseBtn) {
      console.error("AudioPlayer: required DOM elements missing");
      return;
    }

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
          `[data-word-index="${currentWordIndex}"]`,
        );
        old?.classList.remove("word-active");
        old?.classList.add("word-spoken");
      }

      if (idx >= 0) {
        const next = textContainer.querySelector<HTMLElement>(
          `[data-word-index="${idx}"]`,
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
          const el = textContainer.querySelector<HTMLElement>(
            `[data-word-index="${i}"]`,
          );
          if (el) {
            el.classList.remove("word-active");
            el.classList.add("word-spoken");
          }
        }
      } else if (idx >= 0 && idx < currentWordIndex) {
        for (let i = idx + 1; i <= currentWordIndex; i++) {
          const el = textContainer.querySelector<HTMLElement>(
            `[data-word-index="${i}"]`,
          );
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

    audio.src = ctx.dataset.audioUrl;
    applyAudioPrefs();

    ctx.on(audio, "loadedmetadata", () => {
      applyAudioPrefs();
      updateTimeDisplay();
    });
    ctx.on(audio, "durationchange", updateTimeDisplay);

    // Word timings
    fetch(ctx.dataset.timingsUrl)
      .then((r) => r.json())
      .then((data: unknown) => {
        timings = parseWordTimings(data);
        if (textContainer) wordMenuCleanup = attachWordMenu(textContainer);
      })
      .catch((err: unknown) =>
        console.error("AudioPlayer: failed to load timings", err),
      );

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

    // Time updates: progress bars + time display + position report
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
    });
    ctx.on(audio, "pause", () => {
      playPauseBtn.innerHTML = "&#9654;";
      scrollFollow.setPlaying(false);
      stopHighlightLoop();
      ctx.pushEvent("audio_position", {
        position_ms: Math.round(audio.currentTime * 1000),
      });
    });
    ctx.on(audio, "ended", () => {
      stopHighlightLoop();
      if (readerSettings.get().autoNextChapter) ctx.pushEvent("next_chapter");
    });

    // Re-sync UX
    if (resyncBtn) {
      ctx.on(resyncBtn, "click", () => {
        scrollFollow.resume();
        if (currentWordIndex >= 0 && textContainer) {
          const el = textContainer.querySelector<HTMLElement>(
            `[data-word-index="${currentWordIndex}"]`,
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
    });
  },
);
