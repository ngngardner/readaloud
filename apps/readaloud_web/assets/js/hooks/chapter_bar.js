const ChapterBarHook = {
  mounted() {
    this.currentIndex = parseInt(this.el.dataset.currentIndex)
    this.totalChapters = parseInt(this.el.dataset.totalChapters)
    this.chapters = JSON.parse(this.el.dataset.chapters)
    this.bookId = this.el.dataset.bookId
    this.isOpen = false

    this.scrubber = this.el.querySelector("[data-chapter-scrubber]")
    this.fill = this.el.querySelector("[data-scrubber-fill]")
    this.thumb = this.el.querySelector("[data-scrubber-thumb]")
    this.tooltip = this.el.querySelector("[data-scrubber-tooltip]")
    this.strip = this.el.querySelector("[data-chapter-strip]")

    // Set initial scrubber position
    this.setScrubberPosition(this.currentIndex)

    // Scroll strip to center current chapter
    this.scrollStripToIndex(this.currentIndex)

    // Scrubber drag
    this.setupScrubber()

    // Chapter indicator toggle
    const indicator = document.getElementById("chapter-indicator")
    if (indicator) {
      indicator.addEventListener("click", () => this.toggle())
    }

    // Sync isOpen when floating pill hides the bar
    this._pillHideHandler = () => { this.isOpen = false }
    window.addEventListener("chapter-bar-close", this._pillHideHandler)

    // Click outside to close
    this._outsideClickHandler = (e) => {
      if (this.isOpen && !this.el.contains(e.target) && e.target.id !== "chapter-indicator") {
        this.close()
      }
    }
    document.addEventListener("click", this._outsideClickHandler)

    // Chapter pill clicks
    this.el.querySelectorAll("[data-chapter-pill]").forEach(pill => {
      pill.addEventListener("click", () => {
        const idx = parseInt(pill.dataset.chapterPill)
        const ch = this.chapters[idx]
        if (ch && ch.id !== this.chapters[this.currentIndex]?.id) {
          this.pushEvent("jump_to_chapter", { chapter_id: ch.id })
        }
      })
    })
  },

  toggle() {
    this.isOpen ? this.close() : this.open()
  },

  open() {
    this.el.classList.remove("scale-y-0", "opacity-0", "pointer-events-none")
    this.el.classList.add("scale-y-100", "opacity-100")
    this.isOpen = true
  },

  close() {
    this.el.classList.add("scale-y-0", "opacity-0", "pointer-events-none")
    this.el.classList.remove("scale-y-100", "opacity-100")
    this.isOpen = false
  },

  setScrubberPosition(index) {
    const pct = this.totalChapters > 1
      ? (index / (this.totalChapters - 1)) * 100
      : 0
    if (this.fill) this.fill.style.width = pct + "%"
    if (this.thumb) this.thumb.style.left = pct + "%"
  },

  scrollStripToIndex(index) {
    if (!this.strip) return
    const pill = this.strip.children[index]
    if (pill) {
      const stripRect = this.strip.getBoundingClientRect()
      const pillRect = pill.getBoundingClientRect()
      const scrollLeft = pill.offsetLeft - stripRect.width / 2 + pillRect.width / 2
      this.strip.scrollTo({ left: scrollLeft, behavior: "smooth" })
    }
  },

  setupScrubber() {
    if (!this.scrubber) return

    const indexFromClientX = (clientX) => {
      const rect = this.scrubber.getBoundingClientRect()
      const pct = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width))
      return Math.round(pct * (this.totalChapters - 1))
    }

    const showTooltip = (clientX) => {
      const idx = indexFromClientX(clientX)
      const ch = this.chapters[idx]
      if (!ch || !this.tooltip) return
      const label = ch.title || `Chapter ${ch.number}`
      this.tooltip.textContent = `${idx + 1}. ${label}`
      this.tooltip.classList.remove("hidden")
      const rect = this.scrubber.getBoundingClientRect()
      const pct = (clientX - rect.left) / rect.width * 100
      this.tooltip.style.left = pct + "%"
    }

    const hideTooltip = () => {
      if (this.tooltip) this.tooltip.classList.add("hidden")
    }

    let isDragging = false

    // Mouse events
    this.scrubber.addEventListener("mousedown", (e) => {
      isDragging = true
      const idx = indexFromClientX(e.clientX)
      this.setScrubberPosition(idx)
      this.scrollStripToIndex(idx)
      showTooltip(e.clientX)
      e.preventDefault()
    })

    this._onMouseMove = (e) => {
      if (!isDragging) return
      const idx = indexFromClientX(e.clientX)
      this.setScrubberPosition(idx)
      this.scrollStripToIndex(idx)
      showTooltip(e.clientX)
    }

    this._onMouseUp = (e) => {
      if (!isDragging) return
      isDragging = false
      hideTooltip()
      const idx = indexFromClientX(e.clientX)
      const ch = this.chapters[idx]
      if (ch && ch.id !== this.chapters[this.currentIndex]?.id) {
        this.pushEvent("jump_to_chapter", { chapter_id: ch.id })
      }
    }

    window.addEventListener("mousemove", this._onMouseMove)
    window.addEventListener("mouseup", this._onMouseUp)

    // Touch events
    this.scrubber.addEventListener("touchstart", (e) => {
      isDragging = true
      const touch = e.touches[0]
      const idx = indexFromClientX(touch.clientX)
      this.setScrubberPosition(idx)
      this.scrollStripToIndex(idx)
      showTooltip(touch.clientX)
      e.preventDefault()
    }, { passive: false })

    this.scrubber.addEventListener("touchmove", (e) => {
      if (!isDragging) return
      const touch = e.touches[0]
      const idx = indexFromClientX(touch.clientX)
      this.setScrubberPosition(idx)
      this.scrollStripToIndex(idx)
      showTooltip(touch.clientX)
      e.preventDefault()
    }, { passive: false })

    this.scrubber.addEventListener("touchend", (e) => {
      if (!isDragging) return
      isDragging = false
      hideTooltip()
      const touch = e.changedTouches[0]
      if (touch) {
        const idx = indexFromClientX(touch.clientX)
        const ch = this.chapters[idx]
        if (ch && ch.id !== this.chapters[this.currentIndex]?.id) {
          this.pushEvent("jump_to_chapter", { chapter_id: ch.id })
        }
      }
    })
  },

  destroyed() {
    if (this._onMouseMove) window.removeEventListener("mousemove", this._onMouseMove)
    if (this._onMouseUp) window.removeEventListener("mouseup", this._onMouseUp)
    if (this._outsideClickHandler) document.removeEventListener("click", this._outsideClickHandler)
    if (this._pillHideHandler) window.removeEventListener("chapter-bar-close", this._pillHideHandler)
  }
}

export default ChapterBarHook
