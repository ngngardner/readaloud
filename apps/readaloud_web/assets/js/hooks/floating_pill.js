// Any element marked with `data-pill-popover` keeps the pill alive while it's
// visible. Visibility is judged by computed style so this works for both
// `class="hidden"` (display:none) and the chapter-bar's opacity/pointer-events
// closed state.
function isVisible(el) {
	const style = getComputedStyle(el);
	if (style.display === "none") return false;
	if (style.visibility === "hidden") return false;
	if (Number.parseFloat(style.opacity) === 0) return false;
	if (style.pointerEvents === "none") return false;
	return true;
}

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
			this.pill.addEventListener("mouseenter", () =>
				clearTimeout(this.hideTimeout),
			);
			this.pill.addEventListener("mouseleave", () => this.resetTimer(3000));
		}

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
		if (this.hasOpenPopover()) return;
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
	},

	hasOpenPopover() {
		const popovers = document.querySelectorAll("[data-pill-popover]");
		for (const el of popovers) {
			if (isVisible(el)) return true;
		}
		return false;
	},

	destroyed() {
		clearTimeout(this.hideTimeout);
		if (this._docClickHandler)
			document.removeEventListener("click", this._docClickHandler);
		if (this._docMouseMoveHandler)
			document.removeEventListener("mousemove", this._docMouseMoveHandler);
		if (this._togglePillHandler)
			window.removeEventListener("toggle-pill", this._togglePillHandler);
	},
};

export default FloatingPillHook;
