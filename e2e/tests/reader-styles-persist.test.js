/**
 * Regression test: reader settings (fontSize, lineHeight, fontFamily, maxWidth)
 * survive an in-place chapter change.
 *
 * The reader applies these as inline styles on #chapter-text and
 * #reader-content via the ReaderStylesHook. Phoenix LiveView's morphdom
 * strips JS-set attributes that aren't in the server-rendered template
 * when it patches the DOM — so when push_patch swaps the chapter, the
 * inline styles get wiped. The fix re-applies settings in the hook's
 * `updated` lifecycle. This test pins that behavior.
 *
 * Requires the canonical e2e fixture (≥2 chapters). Run via
 * `mix test.e2e` — the Nix VM seeds the fixture before the suite.
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader } from "../helpers.js";

describe("Reader styles persist across chapter swap", () => {
	let browser, page;

	before(async () => {
		({ browser, page } = await setup());
		await openReader(page);
		await page.waitForSelector("#chapter-text", { timeout: 5000 });

		const chapterCount = await page.evaluate(() => {
			const bar = document.getElementById("chapter-bar");
			return bar ? JSON.parse(bar.dataset.chapters).length : 0;
		});
		assert.ok(
			chapterCount >= 2,
			`fixture must seed ≥2 chapters to exercise push_patch; got ${chapterCount}. ` +
				"Check ReadaloudAudiobook.Fixtures.E2E.seed!/1.",
		);
	});

	after(async () => {
		await teardown(browser);
	});

	it("font size on #chapter-text survives next_chapter push_patch", async () => {
		// Pick a font size that's clearly different from the default (18).
		const TARGET_FONT_SIZE = 26;

		// Seed the persisted settings store and force the hook to apply them.
		// We poke the store via localStorage and dispatch a storage-style
		// trigger by re-opening the page so the hook reads the new value
		// on mount. (Going through the slider would also work, but this is
		// faster and doesn't depend on the slider's exact min/max range.)
		await page.evaluate((size) => {
			const raw = localStorage.getItem("readaloud-reader-settings");
			const cur = raw ? JSON.parse(raw) : {};
			cur.fontSize = size;
			localStorage.setItem("readaloud-reader-settings", JSON.stringify(cur));
		}, TARGET_FONT_SIZE);

		await openReader(page);
		await page.waitForSelector("#chapter-text", { timeout: 5000 });

		const initialFontSize = await page.$eval(
			"#chapter-text",
			(el) => el.style.fontSize,
		);
		assert.strictEqual(
			initialFontSize,
			`${TARGET_FONT_SIZE}px`,
			"sanity: hook applied seeded fontSize on initial mount",
		);

		const startingChapterId = await page.evaluate(
			() => window.location.pathname.match(/\/read\/(\d+)/)?.[1],
		);

		// Click the "next chapter" button on the floating pill. This fires
		// a phx-click="next_chapter" → push_patch on the server, which
		// patches the DOM in place (no full page navigation).
		await page.mouse.move(640, 400);
		await page.mouse.move(641, 401);
		await page.waitForSelector("#floating-pill.opacity-100", {
			timeout: 5000,
		});
		await page.click('[phx-click="next_chapter"]:not([disabled])');

		// Wait for the URL to change (push_patch) AND the hook's updated()
		// lifecycle to re-apply the inline style. Both signals are observable
		// in the DOM directly — no need to time-box morphdom's settle.
		await page.waitForFunction(
			(prev, expected) => {
				const m = window.location.pathname.match(/\/read\/(\d+)/);
				const urlChanged = m && m[1] !== prev;
				const styled =
					document.getElementById("chapter-text")?.style.fontSize ===
					`${expected}px`;
				return urlChanged && styled;
			},
			{ timeout: 5000 },
			startingChapterId,
			TARGET_FONT_SIZE,
		);

		const fontSizeAfterSwap = await page.$eval(
			"#chapter-text",
			(el) => el.style.fontSize,
		);
		assert.strictEqual(
			fontSizeAfterSwap,
			`${TARGET_FONT_SIZE}px`,
			"fontSize must survive push_patch chapter swap — without re-apply " +
				"in the hook's updated() lifecycle, morphdom strips the inline " +
				"style and the article reverts to the prose-lg default size",
		);
	});

	it("font family and line height also survive the swap", async () => {
		// We're already on chapter N+1 from the previous test. Set a fresh
		// non-default fontFamily + lineHeight, reload, then swap chapters.
		await page.evaluate(() => {
			const raw = localStorage.getItem("readaloud-reader-settings");
			const cur = raw ? JSON.parse(raw) : {};
			cur.fontFamily = "mono";
			cur.lineHeight = 2.4;
			localStorage.setItem("readaloud-reader-settings", JSON.stringify(cur));
		});

		await openReader(page);
		await page.waitForSelector("#chapter-text", { timeout: 5000 });

		const before = await page.$eval("#chapter-text", (el) => ({
			fontFamily: el.style.fontFamily,
			lineHeight: el.style.lineHeight,
		}));
		assert.match(before.fontFamily, /monospace/i, "sanity: mono applied");
		assert.strictEqual(before.lineHeight, "2.4", "sanity: lineHeight applied");

		const startingChapterId = await page.evaluate(
			() => window.location.pathname.match(/\/read\/(\d+)/)?.[1],
		);

		await page.mouse.move(640, 400);
		await page.mouse.move(641, 401);
		await page.waitForSelector("#floating-pill.opacity-100", {
			timeout: 5000,
		});

		// next_chapter may be disabled if we landed on the last chapter;
		// fall back to prev_chapter in that case.
		const nextDisabled = await page.$eval(
			'[phx-click="next_chapter"]',
			(el) => el.disabled,
		);
		const selector = nextDisabled
			? '[phx-click="prev_chapter"]:not([disabled])'
			: '[phx-click="next_chapter"]:not([disabled])';
		await page.click(selector);

		await page.waitForFunction(
			(prev) => {
				const m = window.location.pathname.match(/\/read\/(\d+)/);
				const urlChanged = m && m[1] !== prev;
				const el = document.getElementById("chapter-text");
				const styled =
					el &&
					/monospace/i.test(el.style.fontFamily) &&
					el.style.lineHeight === "2.4";
				return urlChanged && styled;
			},
			{ timeout: 5000 },
			startingChapterId,
		);

		const after = await page.$eval("#chapter-text", (el) => ({
			fontFamily: el.style.fontFamily,
			lineHeight: el.style.lineHeight,
		}));
		assert.match(
			after.fontFamily,
			/monospace/i,
			"fontFamily must survive chapter swap",
		);
		assert.strictEqual(
			after.lineHeight,
			"2.4",
			"lineHeight must survive chapter swap",
		);
	});
});
