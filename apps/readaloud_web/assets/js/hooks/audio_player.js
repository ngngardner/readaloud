export const AudioPlayer = {
  mounted() {
    this.audio = document.getElementById("audio-element")
    this.playPauseBtn = document.getElementById("play-pause-btn")
    this.progressBar = document.getElementById("progress-bar")
    this.progressFill = document.getElementById("progress-fill")
    this.timeDisplay = document.getElementById("time-display")
    this.textContainer = document.getElementById("chapter-text")
    this.timings = []
    this.segments = []
    this.currentWordIndex = -1
    this.positionReportInterval = null

    // Load audio
    this.audio.src = this.el.dataset.audioUrl

    // Load timings and build segment map
    fetch(this.el.dataset.timingsUrl)
      .then(r => r.json())
      .then(data => {
        this.timings = data.timings || []
        this.segments = this.buildSegments(this.timings)
      })

    // Restore position
    const initialMs = parseInt(this.el.dataset.initialPosition || "0")
    if (initialMs > 0) {
      this.audio.addEventListener("loadedmetadata", () => {
        this.audio.currentTime = initialMs / 1000
      }, { once: true })
    }

    // Play/pause
    this.playPauseBtn.addEventListener("click", () => {
      if (this.audio.paused) {
        this.audio.play()
        this.playPauseBtn.innerHTML = "&#10074;&#10074;"
        this.startHighlighting()
      } else {
        this.audio.pause()
        this.playPauseBtn.innerHTML = "&#9654;"
        this.stopHighlighting()
      }
    })

    // Progress bar seek
    this.progressBar.addEventListener("click", (e) => {
      const rect = this.progressBar.getBoundingClientRect()
      const pct = (e.clientX - rect.left) / rect.width
      this.audio.currentTime = pct * this.audio.duration
    })

    // Time update
    this.audio.addEventListener("timeupdate", () => {
      if (this.audio.duration) {
        const pct = (this.audio.currentTime / this.audio.duration) * 100
        this.progressFill.style.width = pct + "%"
        this.timeDisplay.textContent =
          this.formatTime(this.audio.currentTime) + " / " + this.formatTime(this.audio.duration)
      }
    })

    // Report position every 5 seconds during playback
    this.audio.addEventListener("play", () => {
      this.positionReportInterval = setInterval(() => {
        this.pushEvent("audio_position", {
          position_ms: Math.round(this.audio.currentTime * 1000)
        })
      }, 5000)
    })

    this.audio.addEventListener("pause", () => {
      clearInterval(this.positionReportInterval)
      this.pushEvent("audio_position", {
        position_ms: Math.round(this.audio.currentTime * 1000)
      })
    })
  },

  // Group consecutive words with same start_ms/end_ms into segments.
  // Each segment gets its time range divided evenly among its words.
  buildSegments(timings) {
    if (!timings.length) return []

    const segments = []
    let segStart = 0

    for (let i = 1; i <= timings.length; i++) {
      // New segment when start_ms/end_ms changes or we reach the end
      if (i === timings.length ||
          timings[i].start_ms !== timings[segStart].start_ms ||
          timings[i].end_ms !== timings[segStart].end_ms) {
        const count = i - segStart
        const startMs = timings[segStart].start_ms
        const endMs = timings[segStart].end_ms
        const duration = endMs - startMs

        for (let j = 0; j < count; j++) {
          segments.push({
            index: segStart + j,
            start_ms: startMs + (duration * j / count),
            end_ms: startMs + (duration * (j + 1) / count)
          })
        }
        segStart = i
      }
    }

    return segments
  },

  startHighlighting() {
    const tick = () => {
      if (this.audio.paused) return
      const ms = this.audio.currentTime * 1000
      this.highlightWord(ms)
      requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
  },

  stopHighlighting() {
    const active = this.textContainer.querySelector(".word.active")
    if (active) active.classList.remove("active")
  },

  highlightWord(ms) {
    let idx = -1
    for (let i = 0; i < this.segments.length; i++) {
      if (ms >= this.segments[i].start_ms && ms < this.segments[i].end_ms) {
        idx = this.segments[i].index
        break
      }
    }

    if (idx !== this.currentWordIndex) {
      const old = this.textContainer.querySelector(".word.active")
      if (old) old.classList.remove("active")

      if (idx >= 0) {
        const el = this.textContainer.querySelector(`[data-word-index="${idx}"]`)
        if (el) {
          el.classList.add("active")
          el.scrollIntoView({ behavior: "smooth", block: "center" })
        }
      }

      this.currentWordIndex = idx
    }
  },

  formatTime(secs) {
    const m = Math.floor(secs / 60)
    const s = Math.floor(secs % 60)
    return m + ":" + (s < 10 ? "0" : "") + s
  },

  destroyed() {
    clearInterval(this.positionReportInterval)
    if (this.audio) this.audio.pause()
  }
}
