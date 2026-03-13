/**
 * Smoke test: verifies the app loads and basic navigation works.
 * This test is designed to work in a NixOS VM test environment.
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, BASE_URL, BOOK_ID } from "../helpers.js";

describe("Smoke Test", () => {
	let browser, page;

	before(async () => {
		({ browser, page } = await setup());
	});

	after(async () => {
		await teardown(browser);
	});

	it("library page loads", async () => {
		const response = await page.goto(`${BASE_URL}/`, {
			waitUntil: "networkidle2",
		});
		assert.strictEqual(
			response.status(),
			200,
			"Library page should return 200",
		);
	});

	it("library page has LiveView session", async () => {
		await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle2" });
		const phxSession = await page.$("[data-phx-session]");
		assert.ok(phxSession, "LiveView should be connected");
	});

	it("book page loads with chapter list", async () => {
		const response = await page.goto(`${BASE_URL}/books/${BOOK_ID}`, {
			waitUntil: "networkidle2",
		});
		assert.strictEqual(response.status(), 200, "Book page should return 200");

		// Check that at least one chapter link exists
		const chapterLink = await page.$(`a[href*="/books/${BOOK_ID}/read/"]`);
		assert.ok(chapterLink, "Book page should have at least one chapter link");
	});

	it("reader page loads with chapter content", async () => {
		// Navigate to book page to find a chapter link
		await page.goto(`${BASE_URL}/books/${BOOK_ID}`, {
			waitUntil: "networkidle2",
		});

		const href = await page.evaluate((id) => {
			const link = document.querySelector(`a[href*="/books/${id}/read/"]`);
			return link ? link.getAttribute("href") : null;
		}, BOOK_ID);

		assert.ok(href, "Should find a chapter link on the book page");

		// Navigate to the reader
		const response = await page.goto(`${BASE_URL}${href}?nav=internal`, {
			waitUntil: "networkidle2",
		});
		assert.strictEqual(response.status(), 200, "Reader page should return 200");

		// Wait for LiveView
		await page.waitForSelector("[data-phx-session]", { timeout: 10000 });

		// Check that chapter content rendered
		const content = await page.$("#chapter-text");
		assert.ok(content, "Chapter text should be rendered");

		const text = await page.$eval("#chapter-text", (el) => el.textContent);
		assert.ok(
			text.includes("Test content"),
			`Chapter should contain seeded test content, got: "${text.substring(0, 100)}"`,
		);
	});

	it("floating pill exists in reader", async () => {
		const pill = await page.$("#floating-pill");
		assert.ok(pill, "Floating pill should exist in the DOM");
	});
});
