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

/**
 * Launch browser + page with sensible defaults.
 *
 * When BROWSER_WS_ENDPOINT is set (the VM runs browser-server.js once
 * for the whole suite), connect to the shared Chromium and return an
 * isolated incognito context instead of launching a fresh browser —
 * BrowserContext and Browser expose the same newPage()/close() surface,
 * so callers and teardown() don't care which they got.
 */
export async function setup() {
	const wsEndpoint = process.env.BROWSER_WS_ENDPOINT;
	let browser;
	if (wsEndpoint) {
		const shared = await puppeteer.connect({ browserWSEndpoint: wsEndpoint });
		browser = await shared.createBrowserContext();
	} else {
		browser = await puppeteer.launch({
			headless: HEADLESS,
			args: ["--no-sandbox", "--disable-setuid-sandbox"],
		});
	}
	const page = await browser.newPage();
	await page.setViewport({ width: 1280, height: 800 });
	return { browser, page };
}

/** Close the browser (or the per-file context of the shared browser). */
export async function teardown(browser) {
	if (typeof browser.browser === "function") {
		// Shared-browser mode: `browser` is a per-file BrowserContext.
		// Close it, then disconnect this process's CDP connection — the
		// open websocket otherwise keeps the node:test child process
		// alive forever and the suite hangs after the first file.
		const shared = browser.browser();
		await browser.close();
		await shared.disconnect();
	} else {
		await browser.close();
	}
}

/**
 * Navigate to a reader chapter page and wait for LiveView to mount AND
 * connect its socket.
 *
 * Waits for three signals in order:
 *   1. domcontentloaded — initial (dead-render) HTML parsed
 *   2. [data-phx-session].phx-connected — LiveView socket joined
 *   3. #chapter-text — chapter content present in the DOM
 *
 * (2) is the load-bearing one: [data-phx-session] and #chapter-text
 * both exist in the dead render, but phx-click/pushEvent interactions
 * race the socket join without it. domcontentloaded + .phx-connected is
 * both faster (no 500ms networkidle heuristic per navigation) and a
 * stronger guarantee than the old networkidle2 wait. Tests that need a
 * specific element (e.g. #audio-player when audio_state is :ready)
 * should still `waitForSelector` it explicitly — openReader only
 * guarantees the chapter has rendered and the LV is live.
 */
export async function openReader(page, { bookId, chapterId } = {}) {
	const bid = bookId || BOOK_ID;
	// If no chapterId given, go to the book page first and grab the first chapter link
	if (!chapterId) {
		await page.goto(`${BASE_URL}/books/${bid}`, {
			waitUntil: "domcontentloaded",
		});
		// Find the first "Read" link that points to /books/:id/read/:chapter_id
		const href = await page.evaluate((id) => {
			const link = document.querySelector(`a[href*="/books/${id}/read/"]`);
			return link ? link.getAttribute("href") : null;
		}, bid);
		if (!href) throw new Error(`No chapter link found for book ${bid}`);
		chapterId = href.match(/\/read\/(\d+)/)?.[1];
	}
	const url = `${BASE_URL}/books/${bid}/read/${chapterId}?nav=internal`;
	await page.goto(url, { waitUntil: "domcontentloaded" });
	await page.waitForSelector("[data-phx-session].phx-connected", {
		timeout: 10000,
	});
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
	// Already open? `JS.toggle` would close it. Skip the click in that
	// case — tests call openSettings repeatedly across describe blocks.
	const alreadyOpen = await page.evaluate(() => {
		const el = document.getElementById("reader-settings");
		return el ? getComputedStyle(el).display !== "none" : false;
	});
	if (alreadyOpen) return;
	// Click via puppeteer's API so we get a real CDP click event that
	// Phoenix LV's phx-click handler responds to (synthetic `el.click()`
	// can race the LV command pipeline).
	await gearHandle.click();
	// `JS.toggle` flips the inline `display` style — it does NOT remove
	// the Tailwind `hidden` class (Tailwind's `display: none` is overridden
	// by the inline `display: block`, so `:not(.hidden)` would never match).
	// Wait on the actual visibility instead.
	await page.waitForFunction(
		() => {
			const el = document.getElementById("reader-settings");
			return el && getComputedStyle(el).display !== "none";
		},
		{ timeout: 3000 },
	);
}

/** Get all chapter IDs for a book by reading the chapter bar data attribute. */
export async function getChapters(page) {
	return page.evaluate(() => {
		const bar = document.getElementById("chapter-bar");
		if (!bar) return [];
		return JSON.parse(bar.dataset.chapters);
	});
}
