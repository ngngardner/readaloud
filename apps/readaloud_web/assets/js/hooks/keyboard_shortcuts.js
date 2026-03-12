const KeyboardShortcutsHook = {
  mounted() {
    this.handleKeydown = (e) => {
      if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.isContentEditable) return;

      switch (e.key) {
        case " ":
          e.preventDefault();
          this.pushEvent("toggle_playback");
          break;
        case "ArrowLeft":
          e.preventDefault();
          this.pushEvent("prev_chapter");
          break;
        case "ArrowRight":
          e.preventDefault();
          this.pushEvent("next_chapter");
          break;
        case "+": case "=":
          e.preventDefault();
          this.pushEvent("change_speed", { direction: "up" });
          break;
        case "-":
          e.preventDefault();
          this.pushEvent("change_speed", { direction: "down" });
          break;
        case "Escape":
          e.preventDefault();
          this.pushEvent("toggle_pill");
          break;
        case "m":
          e.preventDefault();
          this.pushEvent("toggle_mute");
          break;
      }
    };

    window.addEventListener("keydown", this.handleKeydown);
  },

  destroyed() {
    window.removeEventListener("keydown", this.handleKeydown);
  }
};

export default KeyboardShortcutsHook;
