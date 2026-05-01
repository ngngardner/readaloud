import { attachWordMenu } from "./word_menu";

const PREF_KEYS = {
	speed: "readaloud-playback-speed",
	volume: "readaloud-volume",
	collapsed: "readaloud-player-collapsed",
};

function loadPrefs() {
	return {
		speed: Number.parseFloat(localStorage.getItem(PREF_KEYS.speed)) || 1,
		volume: Number.parseFloat(localStorage.getItem(PREF_KEYS.volume)) || 1,
		collapsed: localStorage.getItem(PREF_KEYS.collapsed) === "true",
	};
}

function persistPref(key, value) {
	localStorage.setItem(PREF_KEYS[key], String(value));
}

export const AudioPlayer = {
	mounted() {
		this.audio = document.getElementById("audio-element");
		this.playPauseBtn = document.getElementById("play-pause-btn");
		this.timeDisplay = document.getElementById("time-display");
		this.textContainer = document.getElementById("chapter-text");
		this.resyncBtn = document.getElementById("resync-btn");
		this.timings = [];
		this.currentWordIndex = -1;
		this.autoScrollPaused = false;
		this.isAutoScrolling = false;

		// Load and apply persisted prefs (collapsed/volume UI immediately;
		// audio rate/volume reapplied on loadedmetadata for browser-quirk safety).
		this.prefs = loadPrefs();
		if (this.prefs.collapsed) this.el.classList.add("collapsed");

		const volSlider = this.el.querySelector("[data-volume-slider]");
		if (volSlider) volSlider.value = this.prefs.volume;

		this.updateSpeedBadge(this.prefs.speed);

		// Load audio
		this.audio.src = this.el.dataset.audioUrl;

		// Apply audio prefs now AND on every loadedmetadata. Some browsers reset
		// playbackRate when src changes, so re-applying after metadata is the
		// only robust restore point.
		this.applyAudioPrefs();
		this.audio.addEventListener("loadedmetadata", () => {
			this.applyAudioPrefs();
			this.updateTimeDisplay();
		});
		this.audio.addEventListener("durationchange", () =>
			this.updateTimeDisplay(),
		);

		// Load word-level timings; word menu attaches once timings are available.
		fetch(this.el.dataset.timingsUrl)
			.then((r) => r.json())
			.then((data) => {
				this.timings = data.timings || [];
				this._wordMenuCleanup = attachWordMenu(this.textContainer);
			});

		// Restore position
		const initialMs = Number.parseInt(
			this.el.dataset.initialPosition || "0",
			10,
		);
		if (initialMs > 0) {
			this.audio.addEventListener(
				"loadedmetadata",
				() => {
					this.audio.currentTime = initialMs / 1000;
				},
				{ once: true },
			);
		}

		// Play/pause button
		this.playPauseBtn.addEventListener("click", () => this.togglePlayback());

		// Skip back/forward buttons
		const skipBack = this.el.querySelector("[data-skip-back]");
		const skipFwd = this.el.querySelector("[data-skip-forward]");
		if (skipBack)
			skipBack.addEventListener("click", () => {
				this.audio.currentTime = Math.max(0, this.audio.currentTime - 10);
			});
		if (skipFwd)
			skipFwd.addEventListener("click", () => {
				this.audio.currentTime = Math.min(
					this.audio.duration || Number.POSITIVE_INFINITY,
					this.audio.currentTime + 10,
				);
			});

		// Collapse toggle
		const collapseToggle = this.el.querySelector("[data-collapse-toggle]");
		if (collapseToggle) {
			collapseToggle.addEventListener("click", () => {
				const isCollapsed = this.el.classList.toggle("collapsed");
				this.prefs.collapsed = isCollapsed;
				persistPref("collapsed", isCollapsed);
			});
		}

		// Volume slider
		if (volSlider) {
			volSlider.addEventListener("input", () => {
				const vol = Number.parseFloat(volSlider.value);
				this.prefs.volume = vol;
				this.audio.volume = vol;
				persistPref("volume", vol);
			});
		}

		// Scrubber: main + mini
		this._scrubberCleanups = [];
		const scrubber = this.el.querySelector("[data-scrubber]");
		if (scrubber) this.setupScrubber(scrubber);
		const scrubberMini = this.el.querySelector("[data-scrubber-mini]");
		if (scrubberMini) this.setupScrubber(scrubberMini);

		// Time update: progress + time display + position reporting (low frequency)
		this.audio.addEventListener("timeupdate", () => {
			if (!this.audio.duration) return;
			const pct = (this.audio.currentTime / this.audio.duration) * 100;

			const fill = this.el.querySelector("[data-progress-fill]");
			if (fill) fill.style.width = `${pct}%`;
			const fillMini = this.el.querySelector("[data-progress-fill-mini]");
			if (fillMini) fillMini.style.width = `${pct}%`;

			this.updateTimeDisplay();

			// Throttled position report (every ~5s of audio time)
			const nowMs = Math.round(this.audio.currentTime * 1000);
			if (
				!this._lastReportedMs ||
				Math.abs(nowMs - this._lastReportedMs) >= 5000
			) {
				this._lastReportedMs = nowMs;
				this.pushEvent("audio_position", { position_ms: nowMs });
			}
		});

		// High-frequency word highlighting via requestAnimationFrame (60fps)
		this._rafId = null;
		this._startHighlightLoop = () => {
			const tick = () => {
				if (this.audio && !this.audio.paused) {
					this.highlightWord(this.audio.currentTime * 1000);
					this._rafId = requestAnimationFrame(tick);
				}
			};
			this._rafId = requestAnimationFrame(tick);
		};
		this._stopHighlightLoop = () => {
			if (this._rafId) {
				cancelAnimationFrame(this._rafId);
				this._rafId = null;
			}
		};
		this.audio.addEventListener("play", this._startHighlightLoop);
		this.audio.addEventListener("pause", this._stopHighlightLoop);
		this.audio.addEventListener("ended", this._stopHighlightLoop);

		// Play/pause state
		this.audio.addEventListener("play", () => {
			this.playPauseBtn.innerHTML = "&#10074;&#10074;";
			if (this.textContainer) this.textContainer.dataset.audioPlaying = "true";
		});

		this.audio.addEventListener("pause", () => {
			this.playPauseBtn.innerHTML = "&#9654;";
			if (this.textContainer) this.textContainer.dataset.audioPlaying = "false";
			this.pushEvent("audio_position", {
				position_ms: Math.round(this.audio.currentTime * 1000),
			});
		});

		// Auto-advance
		this.audio.addEventListener("ended", () => {
			const settings = this.loadReaderSettings();
			if (settings.autoNextChapter) {
				this.pushEvent("next_chapter", {});
			}
		});

		// Re-sync button
		if (this.resyncBtn) {
			this.resyncBtn.addEventListener("click", () => {
				this.autoScrollPaused = false;
				this.resyncBtn.classList.add("hidden");
				if (this.currentWordIndex >= 0 && this.textContainer) {
					const el = this.textContainer.querySelector(
						`[data-word-index="${this.currentWordIndex}"]`,
					);
					if (el) el.scrollIntoView({ behavior: "smooth", block: "center" });
				}
			});
		}

		// Manual scroll detection from ScrollTracker
		this._manualScrollHandler = () => {
			if (!this.audio.paused && !this.isAutoScrolling) {
				this.autoScrollPaused = true;
				if (this.resyncBtn) this.resyncBtn.classList.remove("hidden");
			}
		};
		window.addEventListener("manual-scroll", this._manualScrollHandler);

		this._autoScrollStartHandler = () => {
			this.isAutoScrolling = true;
		};
		this._autoScrollEndHandler = () => {
			this.isAutoScrolling = false;
		};
		window.addEventListener("auto-scroll-start", this._autoScrollStartHandler);
		window.addEventListener("auto-scroll-end", this._autoScrollEndHandler);

		// Word menu actions (dispatched by WordMenu when user picks "Play from here", etc.)
		this._wordActionHandler = ({ detail }) => {
			if (detail.kind === "play") this.seekToWordIndex(detail.index);
		};
		window.addEventListener("word-action", this._wordActionHandler);

		// Speed badge: cycle on click. No LV round-trip.
		const speedBadge = document.getElementById("speed-badge");
		if (speedBadge) {
			speedBadge.addEventListener("click", () => this.cycleSpeed("up"));
		}

		// Window events from KeyboardShortcuts (no LV round-trip).
		this._togglePlaybackHandler = () => this.togglePlayback();
		this._toggleMuteHandler = () => {
			this.audio.muted = !this.audio.muted;
		};
		this._changeSpeedHandler = ({ detail }) =>
			this.cycleSpeed(detail?.direction || "up");
		window.addEventListener(
			"audio:toggle-playback",
			this._togglePlaybackHandler,
		);
		window.addEventListener("audio:toggle-mute", this._toggleMuteHandler);
		window.addEventListener("audio:change-speed", this._changeSpeedHandler);

		this.setupIntersectionObserver();
	},

	cycleSpeed(direction) {
		const speeds = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
		const cur = this.audio.playbackRate;
		const idx = speeds.findIndex((s) => Math.abs(s - cur) < 0.01);
		const next =
			direction === "up"
				? speeds[Math.min(speeds.length - 1, idx + 1)]
				: speeds[Math.max(0, idx - 1)];
		this.setSpeed(next);
	},

	applyAudioPrefs() {
		this.audio.playbackRate = this.prefs.speed;
		this.audio.volume = this.prefs.volume;
	},

	setupScrubber(scrubber) {
		const getPercent = (clientX) => {
			const rect = scrubber.getBoundingClientRect();
			if (rect.width === 0) return 0;
			return Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
		};

		const seek = (clientX) => {
			if (this.audio.duration && Number.isFinite(this.audio.duration)) {
				const pct = getPercent(clientX);
				this.audio.currentTime = pct * this.audio.duration;
			}
		};

		scrubber.addEventListener("click", (e) => seek(e.clientX));

		let isDragging = false;
		scrubber.addEventListener("mousedown", (e) => {
			isDragging = true;
			seek(e.clientX);
			e.preventDefault();
		});
		const onMouseMove = (e) => {
			if (isDragging) seek(e.clientX);
		};
		const onMouseUp = () => {
			isDragging = false;
		};
		window.addEventListener("mousemove", onMouseMove);
		window.addEventListener("mouseup", onMouseUp);
		this._scrubberCleanups.push(() => {
			window.removeEventListener("mousemove", onMouseMove);
			window.removeEventListener("mouseup", onMouseUp);
		});

		scrubber.addEventListener(
			"touchstart",
			(e) => {
				e.preventDefault();
				seek(e.touches[0].clientX);
			},
			{ passive: false },
		);
		scrubber.addEventListener(
			"touchmove",
			(e) => {
				e.preventDefault();
				seek(e.touches[0].clientX);
			},
			{ passive: false },
		);
		scrubber.addEventListener(
			"touchend",
			(e) => {
				e.preventDefault();
				if (e.changedTouches[0]) seek(e.changedTouches[0].clientX);
			},
			{ passive: false },
		);
	},

	seekToWordIndex(idx) {
		if (idx < 0 || idx >= this.timings.length) return;
		this.audio.currentTime = this.timings[idx].start_ms / 1000;
		if (this.audio.paused) this.audio.play();
	},

	setupIntersectionObserver() {
		if (!this.textContainer || !window.IntersectionObserver) return;
		this._intersectionObserver = new IntersectionObserver(
			(entries) => {
				entries.forEach((entry) => {
					if (entry.isIntersecting && this.autoScrollPaused) {
						this.autoScrollPaused = false;
						if (this.resyncBtn) this.resyncBtn.classList.add("hidden");
					}
				});
			},
			{ threshold: 0.5 },
		);
	},

	togglePlayback() {
		if (this.audio.paused) {
			this.audio.play();
		} else {
			this.audio.pause();
		}
	},

	setSpeed(speed) {
		this.prefs.speed = speed;
		this.audio.playbackRate = speed;
		persistPref("speed", speed);
		this.updateSpeedBadge(speed);
	},

	updateSpeedBadge(speed) {
		const badge = document.getElementById("speed-badge");
		if (badge) {
			badge.textContent = speed === 1 ? "1x" : `${speed}x`;
		}
	},

	highlightWord(ms) {
		if (!this.textContainer || this.timings.length === 0) return;

		// Binary search for active word
		let idx = -1;
		let lo = 0;
		let hi = this.timings.length - 1;

		while (lo <= hi) {
			const mid = (lo + hi) >>> 1;
			const t = this.timings[mid];
			if (ms >= t.start_ms && ms < t.end_ms) {
				idx = mid;
				break;
			} else if (ms < t.start_ms) {
				hi = mid - 1;
			} else {
				idx = mid;
				lo = mid + 1;
			}
		}

		if (idx >= 0 && idx < this.timings.length - 1) {
			const next = this.timings[idx + 1];
			if (ms >= next.start_ms) {
				idx = idx + 1;
			}
		}

		if (idx === this.currentWordIndex) return;

		if (this.currentWordIndex >= 0) {
			const oldActive = this.textContainer.querySelector(
				`[data-word-index="${this.currentWordIndex}"]`,
			);
			if (oldActive) {
				oldActive.classList.remove("word-active");
				oldActive.classList.add("word-spoken");
			}
		}

		if (idx >= 0) {
			const newActive = this.textContainer.querySelector(
				`[data-word-index="${idx}"]`,
			);
			if (newActive) {
				newActive.classList.add("word-active");
				newActive.classList.remove("word-spoken");

				if (!this.autoScrollPaused) {
					window.dispatchEvent(new CustomEvent("auto-scroll-start"));
					newActive.scrollIntoView({ behavior: "smooth", block: "center" });
					clearTimeout(this._autoScrollEndTimer);
					this._autoScrollEndTimer = setTimeout(
						() => window.dispatchEvent(new CustomEvent("auto-scroll-end")),
						800,
					);

					if (this._intersectionObserver) {
						this._intersectionObserver.disconnect();
						this._intersectionObserver.observe(newActive);
					}
				}
			}
		}

		if (idx > this.currentWordIndex) {
			for (let i = Math.max(0, this.currentWordIndex); i < idx; i++) {
				const el = this.textContainer.querySelector(`[data-word-index="${i}"]`);
				if (el) {
					el.classList.remove("word-active");
					el.classList.add("word-spoken");
				}
			}
		} else if (idx >= 0 && idx < this.currentWordIndex) {
			for (let i = idx + 1; i <= this.currentWordIndex; i++) {
				const el = this.textContainer.querySelector(`[data-word-index="${i}"]`);
				if (el) {
					el.classList.remove("word-spoken");
					el.classList.remove("word-active");
				}
			}
		}

		this.currentWordIndex = idx;
	},

	loadReaderSettings() {
		try {
			return JSON.parse(
				localStorage.getItem("readaloud-reader-settings") || "{}",
			);
		} catch {
			return {};
		}
	},

	formatTime(secs) {
		if (!Number.isFinite(secs) || secs < 0) return "0:00";
		const m = Math.floor(secs / 60);
		const s = Math.floor(secs % 60);
		return `${m}:${s < 10 ? "0" : ""}${s}`;
	},

	updateTimeDisplay() {
		if (!this.timeDisplay) return;
		this.timeDisplay.textContent = `${this.formatTime(
			this.audio.currentTime,
		)} / ${this.formatTime(this.audio.duration)}`;
	},

	destroyed() {
		if (this._stopHighlightLoop) this._stopHighlightLoop();
		if (this.audio) this.audio.pause();
		if (this._wordMenuCleanup) this._wordMenuCleanup();
		if (this._wordActionHandler)
			window.removeEventListener("word-action", this._wordActionHandler);
		if (this._togglePlaybackHandler)
			window.removeEventListener(
				"audio:toggle-playback",
				this._togglePlaybackHandler,
			);
		if (this._toggleMuteHandler)
			window.removeEventListener("audio:toggle-mute", this._toggleMuteHandler);
		if (this._changeSpeedHandler)
			window.removeEventListener(
				"audio:change-speed",
				this._changeSpeedHandler,
			);
		if (this._manualScrollHandler)
			window.removeEventListener("manual-scroll", this._manualScrollHandler);
		if (this._autoScrollStartHandler)
			window.removeEventListener(
				"auto-scroll-start",
				this._autoScrollStartHandler,
			);
		if (this._autoScrollEndHandler)
			window.removeEventListener("auto-scroll-end", this._autoScrollEndHandler);
		if (this._intersectionObserver) this._intersectionObserver.disconnect();
		if (this._scrubberCleanups) {
			for (const fn of this._scrubberCleanups) fn();
		}
		clearTimeout(this._autoScrollEndTimer);
	},
};
