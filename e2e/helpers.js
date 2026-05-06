/**
 * Shared helpers for E2E tests.
 *
 * Canonical entry point: `mix test.e2e`, which boots the readaloud
 * release in a NixOS VM, seeds the fixture book via
 * `ReadaloudAudiobook.Fixtures.E2E.seed!/1`, and runs this suite
 * against http://localhost:4000 with BOOK_ID=1.
 *
 * Configurable via env vars (override when running outside the VM):
 *   BASE_URL  - server URL (default: http://localhost:4000)
 *   HEADLESS  - "false" to show the browser (default: true)
 *   BOOK_ID   - book ID to test with (default: 1)
 */
import puppeteer from "puppeteer";

export const BASE_URL = process.env.BASE_URL || "http://localhost:4000";
export const BOOK_ID = process.env.BOOK_ID || "1";
export const HEADLESS = process.env.HEADLESS !== "false";

/** Launch browser + page with sensible defaults. */
export async function setup() {
	const browser = await puppeteer.launch({
		headless: HEADLESS,
		args: ["--no-sandbox", "--disable-setuid-sandbox"],
	});
	const page = await browser.newPage();
	await page.setViewport({ width: 1280, height: 800 });
	return { browser, page };
}

/** Close the browser. */
export async function teardown(browser) {
	await browser.close();
}

/**
 * Navigate to a reader chapter page and wait for LiveView to mount AND
 * finish its first render cycle.
 *
 * Waits for three signals in order:
 *   1. networkidle2 — initial HTML loaded
 *   2. [data-phx-session] — LiveView socket connected
 *   3. #chapter-text — first post-mount render committed to the DOM
 *
 * Without (3), elements gated by mount-time assigns (#audio-player,
 * #speed-badge, etc.) can race the test's first `page.$()` and the
 * test fails with a misleading "selector not found" error. Tests that
 * need a specific element (e.g. #audio-player when audio_state is :ready)
 * should still `waitForSelector` it explicitly — openReader only
 * guarantees the chapter has rendered.
 */
export async function openReader(page, { bookId, chapterId } = {}) {
	const bid = bookId || BOOK_ID;
	// If no chapterId given, go to the book page first and grab the first chapter link
	if (!chapterId) {
		await page.goto(`${BASE_URL}/books/${bid}`, { waitUntil: "networkidle2" });
		// Find the first "Read" link that points to /books/:id/read/:chapter_id
		const href = await page.evaluate((id) => {
			const link = document.querySelector(`a[href*="/books/${id}/read/"]`);
			return link ? link.getAttribute("href") : null;
		}, bid);
		if (!href) throw new Error(`No chapter link found for book ${bid}`);
		chapterId = href.match(/\/read\/(\d+)/)?.[1];
	}
	const url = `${BASE_URL}/books/${bid}/read/${chapterId}?nav=internal`;
	await page.goto(url, { waitUntil: "networkidle2" });
	await page.waitForSelector("[data-phx-session]", { timeout: 10000 });
	await page.waitForSelector("#chapter-text", { timeout: 10000 });
	return { bookId: bid, chapterId };
}

/** Trigger the floating pill to show (mouse move on desktop). */
export async function showPill(page) {
	await page.mouse.move(640, 400);
	await page.mouse.move(641, 401);
	// Wait for opacity transition
	await page.waitForSelector("#floating-pill.opacity-100", { timeout: 5000 });
}

/** Open the settings popover via the gear button. */
export async function openSettings(page) {
	await showPill(page);
	// `#floating-pill button[phx-click]` would match prev/next/gear and
	// hit the first one in DOM order (prev). Walk the buttons explicitly
	// and click the one that contains a hero-cog icon span — robust
	// across :has()-support quirks and DOM ordering changes.
	const gearHandle = await page.evaluateHandle(() => {
		const pill = document.getElementById("floating-pill");
		if (!pill) return null;
		for (const btn of pill.querySelectorAll("button")) {
			if (btn.querySelector('[class*="hero-cog"]')) return btn;
		}
		return null;
	});
	const isElement = await gearHandle.evaluate((el) => el !== null);
	if (!isElement) {
		throw new Error("openSettings: gear button (hero-cog) not found in pill");
	}
	// Click via puppeteer's API so we get a real CDP click event that
	// Phoenix LV's phx-click handler responds to (synthetic `el.click()`
	// can race the LV command pipeline).
	await gearHandle.click();
	await page.waitForSelector("#reader-settings:not(.hidden)", {
		timeout: 3000,
	});
}

/** Get all chapter IDs for a book by reading the chapter bar data attribute. */
export async function getChapters(page) {
	return page.evaluate(() => {
		const bar = document.getElementById("chapter-bar");
		if (!bar) return [];
		return JSON.parse(bar.dataset.chapters);
	});
}
