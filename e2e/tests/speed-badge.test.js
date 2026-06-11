import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader } from "../helpers.js";

describe("Speed Badge", () => {
	let browser, page;

	before(async () => {
		({ browser, page } = await setup());
		// Clear any persisted speed so we start fresh
		await page.evaluateOnNewDocument(() => {
			localStorage.removeItem("readaloud-playback-speed");
		});
		// Pin to chapter 1: the fixture's `audio_for: [1, 2, 3]` guarantees
		// audio there. `openReader()` without args hits BookLive's Resume
		// link, which can point at whichever chapter saved progress
		// reflects — flaky across test ordering.
		await openReader(page, { chapterId: 1 });
		await page.waitForSelector("#audio-player", { timeout: 10000 });
	});

	after(async () => {
		await teardown(browser);
	});

	// The badge only renders when audio_state == :ready, which requires
	// a chapter_audios row. The fixture (`audio_for: [1, 2, 3]`) guarantees
	// chapter 1 has audio, and openReader() lands on chapter 1 by default.
	it("speed badge exists in the audio player", async () => {
		const badge = await page.$("#speed-badge");
		assert.ok(
			badge,
			"speed badge requires audio-ready chapter; check fixture `audio_for`",
		);
	});

	it("badge shows current speed text", async () => {
		const text = await page.$eval("#speed-badge", (el) =>
			el.textContent.trim(),
		);
		assert.match(
			text,
			/^\d+(\.\d+)?x$/,
			`Badge should show speed like "1x", got "${text}"`,
		);
	});

	it("clicking badge cycles speed forward", async () => {
		const initial = await page.$eval("#speed-badge", (el) =>
			el.textContent.trim(),
		);

		await page.click("#speed-badge");
		await page.waitForFunction(
			(prev) =>
				document.getElementById("speed-badge")?.textContent.trim() !== prev,
			{ timeout: 2000 },
			initial,
		);

		const next = await page.$eval("#speed-badge", (el) =>
			el.textContent.trim(),
		);
		assert.notStrictEqual(
			next,
			initial,
			`Speed should change from ${initial} after click`,
		);
	});

	it("speed persists to localStorage", async () => {
		// Player prefs (speed/volume/collapsed) live under a single JSON
		// key — the legacy `readaloud-playback-speed` key is migrated
		// once on boot and never written to again.
		const speed = await page.evaluate(() => {
			const raw = localStorage.getItem("readaloud-player-prefs");
			if (!raw) return null;
			try {
				return JSON.parse(raw).speed;
			} catch {
				return null;
			}
		});
		assert.ok(speed != null, "Speed should be stored in player prefs");
		assert.ok(
			speed > 0,
			`Stored speed should be a positive number, got ${speed}`,
		);
	});

	it("badge uses tabular-nums for stable width", async () => {
		// `tabular-nums` is a Tailwind utility class — it emits a CSS
		// rule, not an inline style — so check the computed value.
		const fontVariant = await page.$eval(
			"#speed-badge",
			(el) => getComputedStyle(el).fontVariantNumeric,
		);
		assert.match(
			fontVariant,
			/tabular-nums/,
			`Badge should use tabular-nums, got ${fontVariant}`,
		);
	});

	it("full cycle wraps back to 0.5x", async () => {
		// Set speed to 2x (last in cycle), then click to wrap
		await page.evaluate(() => {
			const audio = document.getElementById("audio-element");
			if (audio) audio.playbackRate = 2;
			localStorage.setItem("readaloud-playback-speed", "2");
			const b = document.getElementById("speed-badge");
			if (b) b.textContent = "2x";
		});

		await page.click("#speed-badge");
		await page.waitForFunction(
			() =>
				document.getElementById("speed-badge")?.textContent.trim() === "0.5x",
			{ timeout: 2000 },
		);

		const text = await page.$eval("#speed-badge", (el) =>
			el.textContent.trim(),
		);
		assert.strictEqual(text, "0.5x", "Should wrap to 0.5x after 2x");

		// Clean up
		await page.evaluate(() => {
			localStorage.removeItem("readaloud-playback-speed");
		});
	});
});
