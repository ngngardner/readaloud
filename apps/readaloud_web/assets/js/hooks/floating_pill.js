const FloatingPillHook = {
  mounted() {
    this.pill = this.el;
    this.hideTimeout = null;
    this.visible = false;
    const isMobile = window.innerWidth < 640;

    if (isMobile) {
      document.addEventListener("click", (e) => {
        if (e.clientY < 80 && !this.pill.contains(e.target)) {
          this.toggle();
        }
      });
      this.pill.addEventListener("click", () => this.resetTimer(5000));
    } else {
      document.addEventListener("mousemove", () => {
        this.show();
        this.resetTimer(3000);
      });
      this.pill.addEventListener("mouseenter", () => clearTimeout(this.hideTimeout));
      this.pill.addEventListener("mouseleave", () => this.resetTimer(3000));
    }

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
  },

  toggle() {
    this.visible ? this.hide() : this.show();
    if (this.visible) this.resetTimer(5000);
  },

  resetTimer(ms) {
    clearTimeout(this.hideTimeout);
    this.hideTimeout = setTimeout(() => this.hide(), ms);
  }
};

export default FloatingPillHook;
