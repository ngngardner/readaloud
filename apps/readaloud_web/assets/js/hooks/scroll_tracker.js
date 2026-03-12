export const ScrollTracker = {
  mounted() {
    // Restore scroll position
    const initial = parseFloat(this.el.dataset.initialScroll || "0")
    if (initial > 0) {
      requestAnimationFrame(() => {
        this.el.scrollTop = initial * (this.el.scrollHeight - this.el.clientHeight)
      })
    }

    // Track whether auto-scroll is in progress (dispatched by AudioPlayer)
    this._isAutoScrolling = false
    this._autoScrollStartHandler = () => { this._isAutoScrolling = true }
    this._autoScrollEndHandler = () => { this._isAutoScrolling = false }
    window.addEventListener("auto-scroll-start", this._autoScrollStartHandler)
    window.addEventListener("auto-scroll-end", this._autoScrollEndHandler)

    // Debounced scroll tracking
    this._scrollTimeout = null
    this.el.addEventListener("scroll", () => {
      clearTimeout(this._scrollTimeout)
      this._scrollTimeout = setTimeout(() => {
        const scrollable = this.el.scrollHeight - this.el.clientHeight
        const position = scrollable > 0 ? this.el.scrollTop / scrollable : 0
        this.pushEvent("scroll", { position: Math.min(1, Math.max(0, position)) })

        // Detect manual scroll during audio playback
        const isAudioPlaying = this.el.dataset.audioPlaying === "true"
        if (isAudioPlaying && !this._isAutoScrolling) {
          window.dispatchEvent(new CustomEvent("manual-scroll"))
        }
      }, 500)
    })
  },

  destroyed() {
    clearTimeout(this._scrollTimeout)
    if (this._autoScrollStartHandler) window.removeEventListener("auto-scroll-start", this._autoScrollStartHandler)
    if (this._autoScrollEndHandler) window.removeEventListener("auto-scroll-end", this._autoScrollEndHandler)
  }
}
