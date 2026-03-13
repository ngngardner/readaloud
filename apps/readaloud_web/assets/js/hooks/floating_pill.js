const FloatingPillHook = {
  mounted() {
    this.pill = this.el;
    this.hideTimeout = null;
    this.visible = false;
    const isMobile = window.innerWidth < 640;

    if (isMobile) {
      this._docClickHandler = (e) => {
        if (e.clientY < 80 && !this.pill.contains(e.target)) {
          this.toggle();
        }
      };
      document.addEventListener("click", this._docClickHandler);
      this.pill.addEventListener("click", () => this.resetTimer(5000));
    } else {
      this._docMouseMoveHandler = () => {
        this.show();
        this.resetTimer(3000);
      };
      document.addEventListener("mousemove", this._docMouseMoveHandler);
      this.pill.addEventListener("mouseenter", () => clearTimeout(this.hideTimeout));
      this.pill.addEventListener("mouseleave", () => this.resetTimer(3000));
    }

    // Listen for toggle-pill CustomEvent from AudioPlayer (Escape key)
    this._togglePillHandler = () => this.toggle();
    window.addEventListener("toggle-pill", this._togglePillHandler);

    this.hide();
  },

  show() {
    this.pill.classList.remove("opacity-0", "pointer-events-none");
    this.pill.classList.add("opacity-100");
    this.visible = true;
  },

  hide() {
    this.pill.classList.add("opacity-0", "pointer-events-none");
    this.pill.classList.remove("opacity-100");
    this.visible = false;
    // Also collapse the chapter bar via its CSS transition classes
    const chapterBar = document.getElementById("chapter-bar");
    if (chapterBar) {
      chapterBar.classList.add("scale-y-0", "opacity-0", "pointer-events-none");
      chapterBar.classList.remove("scale-y-100", "opacity-100");
    }
  },

  toggle() {
    this.visible ? this.hide() : this.show();
    if (this.visible) this.resetTimer(5000);
  },

  resetTimer(ms) {
    clearTimeout(this.hideTimeout);
    this.hideTimeout = setTimeout(() => this.hide(), ms);
  },

  destroyed() {
    clearTimeout(this.hideTimeout);
    if (this._docClickHandler) document.removeEventListener("click", this._docClickHandler);
    if (this._docMouseMoveHandler) document.removeEventListener("mousemove", this._docMouseMoveHandler);
    if (this._togglePillHandler) window.removeEventListener("toggle-pill", this._togglePillHandler);
  }
};

export default FloatingPillHook;
