export const ScrollTracker = {
  mounted() {
    // Restore scroll position
    const initial = parseFloat(this.el.dataset.initialScroll || "0")
    if (initial > 0) {
      requestAnimationFrame(() => {
        this.el.scrollTop = initial * (this.el.scrollHeight - this.el.clientHeight)
      })
    }

    // Debounced scroll tracking
    let timeout
    this.el.addEventListener("scroll", () => {
      clearTimeout(timeout)
      timeout = setTimeout(() => {
        const position = this.el.scrollTop / (this.el.scrollHeight - this.el.clientHeight)
        this.pushEvent("scroll", { position: Math.min(1, Math.max(0, position)) })
      }, 500)
    })
  }
}
