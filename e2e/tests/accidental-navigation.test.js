import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader, BASE_URL, BOOK_ID } from "../helpers.js";

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

		assert.ok(
			chapters.length >= 3,
			`fixture must seed ≥3 chapters to exercise back-nav conflict; ` +
				`got ${chapters.length}. Check ReadaloudAudiobook.Fixtures.E2E.seed!/1.`,
		);
	});

	after(async () => {
		await teardown(browser);
	});

	it("no popup on initial page load with nav=internal", async () => {
		// Navigate to first chapter with ?nav=internal
		const ch = chapters[0];
		await page.goto(`${BASE_URL}/books/${BOOK_ID}/read/${ch.id}?nav=internal`, {
			waitUntil: "domcontentloaded",
		});
		await page.waitForSelector("[data-phx-session].phx-connected", {
			timeout: 10000,
		});
		await page.waitForSelector("#chapter-text", { timeout: 10000 });
		// nav=internal suppresses the conflict modal — assert that, after
		// the LV has joined (the modal renders post-join if it's going to),
		// the modal hasn't appeared. This is a negative assertion, so wait
		// for the positive signal (connected) and then check.
		await page.waitForFunction(() => document.readyState === "complete", {
			timeout: 2000,
		});

		const modal = await page.$(".modal.modal-open");
		assert.strictEqual(modal, null, "No popup should appear with nav=internal");
	});

	it("popup appears when navigating backward without nav=internal", async () => {
		// First, establish progress at a later chapter (e.g., chapter 3).
		// `?nav=internal` triggers `upsert_progress` synchronously in
		// `handle_params` server-side; that completes before the LV reply.
		// We can't observe the reply directly, but waiting for the chapter
		// content to render is a strong proxy.
		const laterChapter = chapters[Math.min(2, chapters.length - 1)];
		await page.goto(
			`${BASE_URL}/books/${BOOK_ID}/read/${laterChapter.id}?nav=internal`,
			{ waitUntil: "domcontentloaded" },
		);
		await page.waitForSelector("[data-phx-session].phx-connected", {
			timeout: 10000,
		});
		await page.waitForSelector("#chapter-text", { timeout: 10000 });

		// Now navigate to chapter 1 WITHOUT nav=internal — should trigger
		// the conflict modal because saved progress points elsewhere.
		const firstChapter = chapters[0];
		await page.goto(`${BASE_URL}/books/${BOOK_ID}/read/${firstChapter.id}`, {
			waitUntil: "domcontentloaded",
		});
		await page.waitForSelector(".modal.modal-open", { timeout: 5000 });
		// The modal is part of the dead render, so it can show up before
		// the LV socket joins — and a phx-click on its buttons before the
		// join is silently dropped. Wait for the join before proceeding.
		await page.waitForSelector("[data-phx-session].phx-connected", {
			timeout: 10000,
		});

		const modal = await page.$(".modal.modal-open");
		assert.ok(modal, "Conflict popup should appear when navigating backward");
	});

	it("popup shows correct chapter information", async () => {
		// Modal still open from the previous test in this describe block.
		const modal = await page.$(".modal.modal-open");
		assert.ok(modal, "modal must still be open from prior test");

		// `.modal-box` is also rendered (hidden) by the layout's theme
		// modal, which appears first in the DOM — scope the lookup to the
		// open conflict modal so we read its text, not the theme modal's.
		const modalText = await page.$eval(
			".modal.modal-open .modal-box",
			(el) => el.textContent,
		);
		assert.ok(
			modalText.includes("last reading position"),
			`Modal should mention last reading position, got: ${modalText}`,
		);
	});

	it("'Stay' button dismisses popup and stays on current chapter", async () => {
		const modal = await page.$(".modal.modal-open");
		assert.ok(modal, "modal must still be open from prior test");

		// Get current URL before clicking Stay
		const urlBefore = page.url();

		// Click the "Stay" button. The modal-backdrop also wires
		// phx-click="dismiss_conflict" so we scope to .modal-action to land
		// on the button — the backdrop can be obscured under the box and
		// hit-testing into a button is the realistic user gesture anyway.
		await page.click(
			'.modal.modal-open .modal-action [phx-click="dismiss_conflict"]',
		);
		await page.waitForFunction(
			() => document.querySelector(".modal.modal-open") === null,
			{ timeout: 5000 },
		);

		// Modal should be gone
		const modalAfter = await page.$(".modal.modal-open");
		assert.strictEqual(
			modalAfter,
			null,
			"Modal should dismiss after clicking Stay",
		);

		// URL should not change (stayed on same chapter)
		const urlAfter = page.url();
		assert.ok(
			urlAfter.includes(
				urlBefore.split("?")[0].split("/read/")[1]?.split("/")[0] || "",
			),
			"Should stay on the same chapter",
		);
	});

	it("'Go to' button navigates to the conflict chapter", async () => {
		// Re-trigger the conflict: go to later chapter, then navigate back without nav=internal
		const laterChapter = chapters[Math.min(2, chapters.length - 1)];
		await page.goto(
			`${BASE_URL}/books/${BOOK_ID}/read/${laterChapter.id}?nav=internal`,
			{ waitUntil: "domcontentloaded" },
		);
		await page.waitForSelector("[data-phx-session].phx-connected", {
			timeout: 10000,
		});
		await page.waitForSelector("#chapter-text", { timeout: 10000 });

		const firstChapter = chapters[0];
		await page.goto(`${BASE_URL}/books/${BOOK_ID}/read/${firstChapter.id}`, {
			waitUntil: "domcontentloaded",
		});
		await page.waitForSelector(".modal.modal-open", { timeout: 5000 });
		// The modal is part of the dead render, so it can show up before
		// the LV socket joins — and a phx-click on its buttons before the
		// join is silently dropped. Wait for the join before proceeding.
		await page.waitForSelector("[data-phx-session].phx-connected", {
			timeout: 10000,
		});

		const modal = await page.$(".modal.modal-open");
		assert.ok(modal, "Conflict popup should appear after backward nav");

		// Click "Go to" button — select by phx-click within .modal-action.
		await page.click(
			'.modal.modal-open .modal-action [phx-click="go_to_conflict_chapter"]',
		);
		await page.waitForFunction(
			(targetId) => window.location.pathname.includes(`/read/${targetId}`),
			{ timeout: 5000 },
			laterChapter.id,
		);

		// Should have navigated to the later chapter
		const newUrl = page.url();
		assert.ok(
			newUrl.includes(`/read/${laterChapter.id}`),
			`Should navigate to chapter ${laterChapter.id}, got URL: ${newUrl}`,
		);
	});

	it("no popup on forward navigation without nav=internal", async () => {
		// Navigate to first chapter, establish progress.
		const firstChapter = chapters[0];
		await page.goto(
			`${BASE_URL}/books/${BOOK_ID}/read/${firstChapter.id}?nav=internal`,
			{ waitUntil: "domcontentloaded" },
		);
		await page.waitForSelector("[data-phx-session].phx-connected", {
			timeout: 10000,
		});
		await page.waitForSelector("#chapter-text", { timeout: 10000 });

		// Navigate forward to chapter 2 without nav=internal — should NOT
		// trigger the conflict modal (we're moving forward, not back).
		const secondChapter = chapters[1];
		await page.goto(`${BASE_URL}/books/${BOOK_ID}/read/${secondChapter.id}`, {
			waitUntil: "domcontentloaded",
		});
		await page.waitForSelector("[data-phx-session].phx-connected", {
			timeout: 10000,
		});
		await page.waitForSelector("#chapter-text", { timeout: 10000 });

		const modal = await page.$(".modal.modal-open");
		assert.strictEqual(
			modal,
			null,
			"No popup should appear on forward navigation",
		);
	});

	it("no popup on same chapter reload", async () => {
		// Get current chapter
		const url = page.url();
		const chapterMatch = url.match(/\/read\/(\d+)/);
		assert.ok(chapterMatch, `expected reader URL, got ${url}`);

		// Reload without nav=internal — should NOT trigger conflict modal
		// because the chapter we're reloading matches saved progress.
		await page.goto(`${BASE_URL}/books/${BOOK_ID}/read/${chapterMatch[1]}`, {
			waitUntil: "domcontentloaded",
		});
		await page.waitForSelector("[data-phx-session].phx-connected", {
			timeout: 10000,
		});
		await page.waitForSelector("#chapter-text", { timeout: 10000 });

		const modal = await page.$(".modal.modal-open");
		assert.strictEqual(modal, null, "No popup on same chapter reload");
	});
});
