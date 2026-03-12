export const AudioPlayer = {
  mounted() {
    this.audio = document.getElementById("audio-element")
    this.playPauseBtn = document.getElementById("play-pause-btn")
    this.timeDisplay = document.getElementById("time-display")
    this.textContainer = document.getElementById("chapter-text")
    this.resyncBtn = document.getElementById("resync-btn")
    this.timings = []
    this.currentWordIndex = -1
    this.autoScrollPaused = false
    this.isAutoScrolling = false

    // Load persisted state
    const collapsed = localStorage.getItem("readaloud-player-collapsed") === "true"
    if (collapsed) this.el.classList.add("collapsed")

    const savedSpeed = parseFloat(localStorage.getItem("readaloud-playback-speed") || "1")
    this.audio.playbackRate = savedSpeed

    const savedVolume = parseFloat(localStorage.getItem("readaloud-volume") || "1")
    this.audio.volume = savedVolume

    // Update volume slider UI
    const volSlider = this.el.querySelector("[data-volume-slider]")
    if (volSlider) volSlider.value = savedVolume

    // Update speed button active state
    this.updateSpeedButtons(savedSpeed)

    // Load audio
    this.audio.src = this.el.dataset.audioUrl

    // Load word-level timings
    fetch(this.el.dataset.timingsUrl)
      .then(r => r.json())
      .then(data => {
        this.timings = data.timings || []
        // Set up click-to-seek on word spans
        this.setupWordClickListeners()
      })

    // Restore position
    const initialMs = parseInt(this.el.dataset.initialPosition || "0")
    if (initialMs > 0) {
      this.audio.addEventListener("loadedmetadata", () => {
        this.audio.currentTime = initialMs / 1000
      }, { once: true })
    }

    // Play/pause button
    this.playPauseBtn.addEventListener("click", () => this.togglePlayback())

    // Skip back/forward buttons
    const skipBack = this.el.querySelector("[data-skip-back]")
    const skipFwd = this.el.querySelector("[data-skip-forward]")
    if (skipBack) skipBack.addEventListener("click", () => { this.audio.currentTime = Math.max(0, this.audio.currentTime - 10) })
    if (skipFwd) skipFwd.addEventListener("click", () => { this.audio.currentTime = Math.min(this.audio.duration || Infinity, this.audio.currentTime + 10) })

    // Collapse toggle
    const collapseToggle = this.el.querySelector("[data-collapse-toggle]")
    if (collapseToggle) {
      collapseToggle.addEventListener("click", () => {
        const isCollapsed = this.el.classList.toggle("collapsed")
        localStorage.setItem("readaloud-player-collapsed", isCollapsed)
      })
    }

    // Speed buttons
    this.el.querySelectorAll("[data-speed]").forEach(btn => {
      btn.addEventListener("click", () => {
        const speed = parseFloat(btn.dataset.speed)
        this.setSpeed(speed)
      })
    })

    // Volume slider
    if (volSlider) {
      volSlider.addEventListener("input", () => {
        const vol = parseFloat(volSlider.value)
        this.audio.volume = vol
        localStorage.setItem("readaloud-volume", vol)
      })
    }

    // Scrubber: main + mini (store window listeners for cleanup)
    this._scrubberCleanups = []
    const scrubber = this.el.querySelector("[data-scrubber]")
    if (scrubber) {
      this.setupScrubber(scrubber)
    }

    const scrubberMini = this.el.querySelector("[data-scrubber-mini]")
    if (scrubberMini) {
      this.setupScrubber(scrubberMini)
    }

    // Fallback: old progress-bar ID if present
    const progressBar = document.getElementById("progress-bar")
    if (progressBar && !scrubber && !scrubberMini) {
      progressBar.addEventListener("click", (e) => {
        const rect = progressBar.getBoundingClientRect()
        const pct = (e.clientX - rect.left) / rect.width
        this.audio.currentTime = pct * this.audio.duration
      })
    }

    // Time update: progress + time display + position reporting (low frequency)
    this.audio.addEventListener("timeupdate", () => {
      if (this.audio.duration) {
        const pct = (this.audio.currentTime / this.audio.duration) * 100

        // Update scrubber fills (main + mini)
        const fill = this.el.querySelector("[data-progress-fill]") || document.getElementById("progress-fill")
        if (fill) fill.style.width = pct + "%"
        const fillMini = this.el.querySelector("[data-progress-fill-mini]")
        if (fillMini) fillMini.style.width = pct + "%"

        if (this.timeDisplay) {
          this.timeDisplay.textContent =
            this.formatTime(this.audio.currentTime) + " / " + this.formatTime(this.audio.duration)
        }

        // Report position (throttled: every ~5s of audio time)
        const nowMs = Math.round(this.audio.currentTime * 1000)
        if (!this._lastReportedMs || Math.abs(nowMs - this._lastReportedMs) >= 5000) {
          this._lastReportedMs = nowMs
          this.pushEvent("audio_position", { position_ms: nowMs })
        }
      }
    })

    // High-frequency word highlighting via requestAnimationFrame (60fps)
    this._rafId = null
    this._startHighlightLoop = () => {
      const tick = () => {
        if (this.audio && !this.audio.paused) {
          this.highlightWord(this.audio.currentTime * 1000)
          this._rafId = requestAnimationFrame(tick)
        }
      }
      this._rafId = requestAnimationFrame(tick)
    }
    this._stopHighlightLoop = () => {
      if (this._rafId) {
        cancelAnimationFrame(this._rafId)
        this._rafId = null
      }
    }
    this.audio.addEventListener("play", this._startHighlightLoop)
    this.audio.addEventListener("pause", this._stopHighlightLoop)
    this.audio.addEventListener("ended", this._stopHighlightLoop)

    // Play/pause state
    this.audio.addEventListener("play", () => {
      this.playPauseBtn.innerHTML = "&#10074;&#10074;"
      if (this.textContainer) this.textContainer.dataset.audioPlaying = "true"
    })

    this.audio.addEventListener("pause", () => {
      this.playPauseBtn.innerHTML = "&#9654;"
      if (this.textContainer) this.textContainer.dataset.audioPlaying = "false"
      this.pushEvent("audio_position", {
        position_ms: Math.round(this.audio.currentTime * 1000)
      })
    })

    // Auto-advance
    this.audio.addEventListener("ended", () => {
      const settings = this.loadReaderSettings()
      if (settings.autoNextChapter) {
        this.pushEvent("next_chapter", {})
      }
    })

    // Re-sync button
    if (this.resyncBtn) {
      this.resyncBtn.addEventListener("click", () => {
        this.autoScrollPaused = false
        this.resyncBtn.classList.add("hidden")
        // Force scroll to current word
        if (this.currentWordIndex >= 0 && this.textContainer) {
          const el = this.textContainer.querySelector(`[data-word-index="${this.currentWordIndex}"]`)
          if (el) el.scrollIntoView({ behavior: "smooth", block: "center" })
        }
      })
    }

    // Manual scroll detection from ScrollTracker
    this._manualScrollHandler = () => {
      if (!this.audio.paused && !this.isAutoScrolling) {
        this.autoScrollPaused = true
        if (this.resyncBtn) this.resyncBtn.classList.remove("hidden")
      }
    }
    window.addEventListener("manual-scroll", this._manualScrollHandler)

    // Auto-scroll lifecycle events
    this._autoScrollStartHandler = () => { this.isAutoScrolling = true }
    this._autoScrollEndHandler = () => { this.isAutoScrolling = false }
    window.addEventListener("auto-scroll-start", this._autoScrollStartHandler)
    window.addEventListener("auto-scroll-end", this._autoScrollEndHandler)

    // LiveView event handlers
    this.handleEvent("toggle_audio", () => this.togglePlayback())
    this.handleEvent("toggle_mute", () => {
      this.audio.muted = !this.audio.muted
    })
    this.handleEvent("change_speed", ({ direction }) => {
      const speeds = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
      const cur = this.audio.playbackRate
      const idx = speeds.findIndex(s => Math.abs(s - cur) < 0.01)
      let next
      if (direction === "up") next = speeds[Math.min(speeds.length - 1, idx + 1)]
      else next = speeds[Math.max(0, idx - 1)]
      this.setSpeed(next)
    })
    this.handleEvent("toggle_pill", () => {
      // Delegate to FloatingPillHook via CustomEvent
      window.dispatchEvent(new CustomEvent("toggle-pill"))
    })

    // Set up IntersectionObserver for auto-restore of re-sync state
    this.setupIntersectionObserver()
  },

  setupScrubber(scrubber) {
    const getPercent = (clientX) => {
      const rect = scrubber.getBoundingClientRect()
      if (rect.width === 0) return 0
      return Math.min(1, Math.max(0, (clientX - rect.left) / rect.width))
    }

    const seek = (clientX) => {
      if (this.audio.duration && isFinite(this.audio.duration)) {
        const pct = getPercent(clientX)
        this.audio.currentTime = pct * this.audio.duration
      }
    }

    // Click handler (simple single-click seek)
    scrubber.addEventListener("click", (e) => {
      seek(e.clientX)
    })

    // Mouse drag events
    let isDragging = false
    scrubber.addEventListener("mousedown", (e) => {
      isDragging = true
      seek(e.clientX)
      e.preventDefault()
    })
    const onMouseMove = (e) => { if (isDragging) seek(e.clientX) }
    const onMouseUp = () => { isDragging = false }
    window.addEventListener("mousemove", onMouseMove)
    window.addEventListener("mouseup", onMouseUp)
    this._scrubberCleanups.push(
      () => { window.removeEventListener("mousemove", onMouseMove); window.removeEventListener("mouseup", onMouseUp) }
    )

    // Touch events
    scrubber.addEventListener("touchstart", (e) => {
      e.preventDefault()
      seek(e.touches[0].clientX)
    }, { passive: false })
    scrubber.addEventListener("touchmove", (e) => {
      e.preventDefault()
      seek(e.touches[0].clientX)
    }, { passive: false })
    scrubber.addEventListener("touchend", (e) => {
      e.preventDefault()
      if (e.changedTouches[0]) seek(e.changedTouches[0].clientX)
    }, { passive: false })
  },

  setupWordClickListeners() {
    if (!this.textContainer) return
    this.textContainer.querySelectorAll("[data-word-index]").forEach(el => {
      el.addEventListener("click", () => {
        const idx = parseInt(el.dataset.wordIndex)
        if (idx >= 0 && idx < this.timings.length) {
          this.audio.currentTime = this.timings[idx].start_ms / 1000
          if (this.audio.paused) this.audio.play()
        }
      })
    })
  },

  setupIntersectionObserver() {
    if (!this.textContainer || !window.IntersectionObserver) return
    this._intersectionObserver = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting && this.autoScrollPaused) {
          this.autoScrollPaused = false
          if (this.resyncBtn) this.resyncBtn.classList.add("hidden")
        }
      })
    }, { threshold: 0.5 })
  },

  togglePlayback() {
    if (this.audio.paused) {
      this.audio.play()
    } else {
      this.audio.pause()
    }
  },

  setSpeed(speed) {
    this.audio.playbackRate = speed
    localStorage.setItem("readaloud-playback-speed", speed)
    this.updateSpeedButtons(speed)
  },

  updateSpeedButtons(speed) {
    this.el.querySelectorAll("[data-speed]").forEach(btn => {
      const btnSpeed = parseFloat(btn.dataset.speed)
      btn.classList.toggle("btn-active", Math.abs(btnSpeed - speed) < 0.01)
    })
  },

  highlightWord(ms) {
    if (!this.textContainer || this.timings.length === 0) return

    // Binary search for active word (matches ln-reader approach)
    let idx = -1
    let lo = 0
    let hi = this.timings.length - 1

    while (lo <= hi) {
      const mid = (lo + hi) >>> 1
      const t = this.timings[mid]
      if (ms >= t.start_ms && ms < t.end_ms) {
        idx = mid
        break
      } else if (ms < t.start_ms) {
        hi = mid - 1
      } else {
        // ms >= t.end_ms — keep track of the last word we passed
        idx = mid
        lo = mid + 1
      }
    }

    // If we landed past a word, check if we're actually in the next one
    if (idx >= 0 && idx < this.timings.length - 1) {
      const next = this.timings[idx + 1]
      if (ms >= next.start_ms) {
        idx = idx + 1
      }
    }

    if (idx === this.currentWordIndex) return

    // Remove old active/spoken classes
    if (this.currentWordIndex >= 0) {
      const oldActive = this.textContainer.querySelector(`[data-word-index="${this.currentWordIndex}"]`)
      if (oldActive) {
        oldActive.classList.remove("word-active")
        oldActive.classList.add("word-spoken")
      }
    }

    // Add new active word
    if (idx >= 0) {
      const newActive = this.textContainer.querySelector(`[data-word-index="${idx}"]`)
      if (newActive) {
        newActive.classList.add("word-active")
        newActive.classList.remove("word-spoken")

        // Auto-scroll to active word if not paused by user
        if (!this.autoScrollPaused) {
          window.dispatchEvent(new CustomEvent("auto-scroll-start"))
          newActive.scrollIntoView({ behavior: "smooth", block: "center" })
          // Clear previous timeout to prevent overlap at high playback speeds
          clearTimeout(this._autoScrollEndTimer)
          this._autoScrollEndTimer = setTimeout(() => window.dispatchEvent(new CustomEvent("auto-scroll-end")), 800)

          // IntersectionObserver: watch the active word
          if (this._intersectionObserver) {
            this._intersectionObserver.disconnect()
            this._intersectionObserver.observe(newActive)
          }
        }
      }
    }

    // Apply word-spoken to all words before current index
    // Only update the range that changed to avoid full re-scan
    if (idx > this.currentWordIndex) {
      for (let i = Math.max(0, this.currentWordIndex); i < idx; i++) {
        const el = this.textContainer.querySelector(`[data-word-index="${i}"]`)
        if (el) {
          el.classList.remove("word-active")
          el.classList.add("word-spoken")
        }
      }
    } else if (idx >= 0 && idx < this.currentWordIndex) {
      // Seeked backwards: remove spoken from words after new index
      for (let i = idx + 1; i <= this.currentWordIndex; i++) {
        const el = this.textContainer.querySelector(`[data-word-index="${i}"]`)
        if (el) {
          el.classList.remove("word-spoken")
          el.classList.remove("word-active")
        }
      }
    }

    this.currentWordIndex = idx
  },

  loadReaderSettings() {
    try {
      return JSON.parse(localStorage.getItem("readaloud-reader-settings") || "{}")
    } catch {
      return {}
    }
  },

  formatTime(secs) {
    const m = Math.floor(secs / 60)
    const s = Math.floor(secs % 60)
    return m + ":" + (s < 10 ? "0" : "") + s
  },

  destroyed() {
    if (this._stopHighlightLoop) this._stopHighlightLoop()
    if (this.audio) this.audio.pause()
    if (this._manualScrollHandler) window.removeEventListener("manual-scroll", this._manualScrollHandler)
    if (this._autoScrollStartHandler) window.removeEventListener("auto-scroll-start", this._autoScrollStartHandler)
    if (this._autoScrollEndHandler) window.removeEventListener("auto-scroll-end", this._autoScrollEndHandler)
    if (this._intersectionObserver) this._intersectionObserver.disconnect()
    if (this._scrubberCleanups) this._scrubberCleanups.forEach(fn => fn())
    clearTimeout(this._autoScrollEndTimer)
  }
}
