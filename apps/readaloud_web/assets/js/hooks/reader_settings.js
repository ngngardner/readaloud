const SETTINGS_KEY = "readaloud-reader-settings";

const defaults = {
	fontFamily: "serif",
	fontSize: 18,
	lineHeight: 1.8,
	maxWidth: 700,
	autoScroll: true,
	autoNextChapter: false,
};

const ReaderSettingsHook = {
	mounted() {
		this.settings = {
			...defaults,
			...JSON.parse(localStorage.getItem(SETTINGS_KEY) || "{}"),
		};
		this.applySettings();
		this.syncAutoNextToggle();

		this.handleEvent("update_reader_setting", ({ key, value }) => {
			if (key === "autoNextChapter" && value === "toggle") {
				this.settings[key] = !this.settings[key];
			} else {
				this.settings[key] = value;
			}
			localStorage.setItem(SETTINGS_KEY, JSON.stringify(this.settings));
			this.applySettings();
			if (key === "autoNextChapter") this.syncAutoNextToggle();
		});
	},

	syncAutoNextToggle() {
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
		content.style.fontFamily = fonts[this.settings.fontFamily] || fonts.serif;
		content.style.fontSize = `${this.settings.fontSize}px`;
		content.style.lineHeight = this.settings.lineHeight;
		content.style.maxWidth = `${this.settings.maxWidth}px`;
	},
};

export default ReaderSettingsHook;
