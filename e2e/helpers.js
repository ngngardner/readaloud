/**
 * Shared helpers for E2E tests.
 *
 * Expects a running Phoenix dev server. Configure with env vars:
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
 * Navigate to a reader chapter page and wait for LiveView to mount.
 * Returns the chapter URL used.
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
  // Wait for LiveView to be connected (phx-connected attribute appears)
  await page.waitForSelector("[data-phx-session]", { timeout: 10000 });
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
  await page.click("#floating-pill button[phx-click]");
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

/** Small sleep helper for animation waits. */
export function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}
