import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader, sleep, BASE_URL, BOOK_ID } from "../helpers.js";

describe("Accidental Navigation Popup", () => {
  let browser, page, chapters;

  before(async () => {
    ({ browser, page } = await setup());

    // First, open a later chapter to establish reading progress
    const { chapterId: firstChapterId } = await openReader(page);

    // Get all chapters from the chapter bar data
    chapters = await page.evaluate(() => {
      const bar = document.getElementById("chapter-bar");
      return bar ? JSON.parse(bar.dataset.chapters) : [];
    });

    if (chapters.length < 3) {
      console.log("  (book has fewer than 3 chapters — some tests will be skipped)");
    }
  });

  after(async () => {
    await teardown(browser);
  });

  it("no popup on initial page load with nav=internal", async () => {
    // Navigate to first chapter with ?nav=internal
    const ch = chapters[0];
    if (!ch) return;

    await page.goto(
      `${BASE_URL}/books/${BOOK_ID}/read/${ch.id}?nav=internal`,
      { waitUntil: "networkidle2" }
    );
    await sleep(500);

    const modal = await page.$(".modal.modal-open");
    assert.strictEqual(modal, null, "No popup should appear with nav=internal");
  });

  it("popup appears when navigating backward without nav=internal", async () => {
    if (chapters.length < 3) return;

    // First, establish progress at a later chapter (e.g., chapter 3)
    const laterChapter = chapters[Math.min(2, chapters.length - 1)];
    await page.goto(
      `${BASE_URL}/books/${BOOK_ID}/read/${laterChapter.id}?nav=internal`,
      { waitUntil: "networkidle2" }
    );
    await page.waitForSelector("[data-phx-session]", { timeout: 10000 });
    await sleep(1000); // Wait for progress to save

    // Now navigate to chapter 1 WITHOUT nav=internal (simulating stale tab)
    const firstChapter = chapters[0];
    await page.goto(
      `${BASE_URL}/books/${BOOK_ID}/read/${firstChapter.id}`,
      { waitUntil: "networkidle2" }
    );
    await page.waitForSelector("[data-phx-session]", { timeout: 10000 });
    await sleep(500);

    const modal = await page.$(".modal.modal-open");
    assert.ok(modal, "Conflict popup should appear when navigating backward");
  });

  it("popup shows correct chapter information", async () => {
    const modal = await page.$(".modal.modal-open");
    if (!modal) return; // skip if popup didn't show (from previous test)

    const modalText = await page.$eval(".modal-box", (el) => el.textContent);
    assert.ok(
      modalText.includes("last reading position"),
      "Modal should mention last reading position"
    );
  });

  it("'Stay' button dismisses popup and stays on current chapter", async () => {
    const modal = await page.$(".modal.modal-open");
    if (!modal) return;

    // Get current URL before clicking Stay
    const urlBefore = page.url();

    // Click the "Stay" button (btn-ghost)
    await page.click('.modal-action .btn-ghost');
    await sleep(500);

    // Modal should be gone
    const modalAfter = await page.$(".modal.modal-open");
    assert.strictEqual(modalAfter, null, "Modal should dismiss after clicking Stay");

    // URL should not change (stayed on same chapter)
    const urlAfter = page.url();
    assert.ok(
      urlAfter.includes(urlBefore.split("?")[0].split("/read/")[1]?.split("/")[0] || ""),
      "Should stay on the same chapter"
    );
  });

  it("'Go to' button navigates to the conflict chapter", async () => {
    if (chapters.length < 3) return;

    // Re-trigger the conflict: go to later chapter, then navigate back without nav=internal
    const laterChapter = chapters[Math.min(2, chapters.length - 1)];
    await page.goto(
      `${BASE_URL}/books/${BOOK_ID}/read/${laterChapter.id}?nav=internal`,
      { waitUntil: "networkidle2" }
    );
    await page.waitForSelector("[data-phx-session]", { timeout: 10000 });
    await sleep(1000);

    const firstChapter = chapters[0];
    await page.goto(
      `${BASE_URL}/books/${BOOK_ID}/read/${firstChapter.id}`,
      { waitUntil: "networkidle2" }
    );
    await page.waitForSelector("[data-phx-session]", { timeout: 10000 });
    await sleep(500);

    const modal = await page.$(".modal.modal-open");
    if (!modal) {
      console.log("  (skipped: popup didn't appear)");
      return;
    }

    // Click "Go to" button (btn-primary)
    await page.click('.modal-action .btn-primary');
    await sleep(1000);

    // Should have navigated to the later chapter
    const newUrl = page.url();
    assert.ok(
      newUrl.includes(`/read/${laterChapter.id}`),
      `Should navigate to chapter ${laterChapter.id}, got URL: ${newUrl}`
    );
  });

  it("no popup on forward navigation without nav=internal", async () => {
    if (chapters.length < 2) return;

    // Navigate to first chapter, establish progress
    const firstChapter = chapters[0];
    await page.goto(
      `${BASE_URL}/books/${BOOK_ID}/read/${firstChapter.id}?nav=internal`,
      { waitUntil: "networkidle2" }
    );
    await page.waitForSelector("[data-phx-session]", { timeout: 10000 });
    await sleep(1000);

    // Navigate forward to chapter 2 without nav=internal
    const secondChapter = chapters[1];
    await page.goto(
      `${BASE_URL}/books/${BOOK_ID}/read/${secondChapter.id}`,
      { waitUntil: "networkidle2" }
    );
    await page.waitForSelector("[data-phx-session]", { timeout: 10000 });
    await sleep(500);

    const modal = await page.$(".modal.modal-open");
    assert.strictEqual(
      modal,
      null,
      "No popup should appear on forward navigation"
    );
  });

  it("no popup on same chapter reload", async () => {
    // Get current chapter
    const url = page.url();
    const chapterMatch = url.match(/\/read\/(\d+)/);
    if (!chapterMatch) return;

    // Reload without nav=internal
    await page.goto(
      `${BASE_URL}/books/${BOOK_ID}/read/${chapterMatch[1]}`,
      { waitUntil: "networkidle2" }
    );
    await page.waitForSelector("[data-phx-session]", { timeout: 10000 });
    await sleep(500);

    const modal = await page.$(".modal.modal-open");
    assert.strictEqual(modal, null, "No popup on same chapter reload");
  });
});
