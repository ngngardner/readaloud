const SETTINGS_KEY = "readaloud-reader-settings";

const defaults = {
	fontFamily: "serif",
	fontSize: 18,
	lineHeight: 1.8,
	maxWidth: 700,
	autoScroll: true,
	autoNextChapter: false,
};

const RANGE_KEYS = ["fontSize", "lineHeight", "maxWidth"];

const ReaderSettingsHook = {
	mounted() {
		this.settings = {
			...defaults,
			...JSON.parse(localStorage.getItem(SETTINGS_KEY) || "{}"),
		};
		this.applySettings();
		this.syncControls();
		this.bindSettingsControls();
	},

	bindSettingsControls() {
		const popover = document.getElementById("reader-settings");
		if (!popover) return;

		// Font family — buttons carry data-font-family.
		this._fontHandlers = [];
		popover.querySelectorAll("[data-font-family]").forEach((btn) => {
			const handler = () => this.update("fontFamily", btn.dataset.fontFamily);
			btn.addEventListener("click", handler);
			this._fontHandlers.push([btn, handler]);
		});

		// Range inputs — name attribute matches the settings key.
		this._rangeHandlers = [];
		popover.querySelectorAll("input[type=range][name]").forEach((input) => {
			const handler = () =>
				this.update(input.name, Number.parseFloat(input.value));
			input.addEventListener("input", handler);
			this._rangeHandlers.push([input, handler]);
		});

		// Auto-next-chapter toggle.
		const toggle = document.getElementById("auto-next-chapter-toggle");
		if (toggle) {
			this._autoNextHandler = () =>
				this.update("autoNextChapter", toggle.checked);
			toggle.addEventListener("change", this._autoNextHandler);
		}
	},

	update(key, value) {
		this.settings[key] = value;
		localStorage.setItem(SETTINGS_KEY, JSON.stringify(this.settings));
		this.applySettings();
	},

	syncControls() {
		const popover = document.getElementById("reader-settings");
		if (popover) {
			for (const key of RANGE_KEYS) {
				const input = popover.querySelector(`input[type=range][name="${key}"]`);
				if (input && this.settings[key] != null)
					input.value = this.settings[key];
			}
		}
		const toggle = document.getElementById("auto-next-chapter-toggle");
		if (toggle) toggle.checked = !!this.settings.autoNextChapter;
	},

	applySettings() {
		const content = document.getElementById("reader-content");
		if (!content) return;

		const fonts = {
			serif: "Georgia, serif",
			sans: "'Inter', sans-serif",
			mono: "ui-monospace, monospace",
		};
		content.style.maxWidth = `${this.settings.maxWidth}px`;

		const article = document.getElementById("chapter-text");
		if (article) {
			article.style.fontFamily = fonts[this.settings.fontFamily] || fonts.serif;
			article.style.fontSize = `${this.settings.fontSize}px`;
			article.style.lineHeight = this.settings.lineHeight;
		}
	},

	destroyed() {
		if (this._fontHandlers) {
			for (const [btn, handler] of this._fontHandlers) {
				btn.removeEventListener("click", handler);
			}
		}
		if (this._rangeHandlers) {
			for (const [input, handler] of this._rangeHandlers) {
				input.removeEventListener("input", handler);
			}
		}
		const toggle = document.getElementById("auto-next-chapter-toggle");
		if (toggle && this._autoNextHandler) {
			toggle.removeEventListener("change", this._autoNextHandler);
		}
	},
};

export default ReaderSettingsHook;
