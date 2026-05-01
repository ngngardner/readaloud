// Keyboard shortcuts that don't require server work dispatch a window event
// directly. Only chapter navigation (which mutates server state) goes through
// pushEvent.
const dispatchWin = (name, detail) =>
	window.dispatchEvent(new CustomEvent(name, { detail }));

const KeyboardShortcutsHook = {
	mounted() {
		this.handleKeydown = (e) => {
			if (
				e.target.tagName === "INPUT" ||
				e.target.tagName === "TEXTAREA" ||
				e.target.isContentEditable
			)
				return;

			switch (e.key) {
				case " ":
					e.preventDefault();
					dispatchWin("audio:toggle-playback");
					break;
				case "ArrowLeft":
					e.preventDefault();
					this.pushEvent("prev_chapter");
					break;
				case "ArrowRight":
					e.preventDefault();
					this.pushEvent("next_chapter");
					break;
				case "+":
				case "=":
					e.preventDefault();
					dispatchWin("audio:change-speed", { direction: "up" });
					break;
				case "-":
					e.preventDefault();
					dispatchWin("audio:change-speed", { direction: "down" });
					break;
				case "Escape":
					e.preventDefault();
					dispatchWin("toggle-pill");
					break;
				case "m":
					e.preventDefault();
					dispatchWin("audio:toggle-mute");
					break;
			}
		};

		window.addEventListener("keydown", this.handleKeydown);
	},

	destroyed() {
		window.removeEventListener("keydown", this.handleKeydown);
	},
};

export default KeyboardShortcutsHook;
