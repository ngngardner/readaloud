/**
 * Manual chapter-nav test (floating-pill next button).
 *
 * Regression for: clicking the pill's next-chapter button during
 * playback used to route through the server-owned `phx-click="next_chapter"`
 * → `push_patch` path, which re-rendered the page but left the
 * `<audio>` element (preserved via `phx-update="ignore"`) playing the
 * OLD chapter — and the hook's `data-chapter-id` flip meant subsequent
 * `timeupdate` writes used the new chapter id with the old audio
 * position, corrupting progress.
 *
 * With the fix, when `audio_state == :ready`, the pill button uses
 * `JS.dispatch("audio:nav-next-chapter")` which the AudioPlayerHook
 * picks up and routes through `goToNextChapter` — same-<audio>-element
 * src swap + `history.pushState` + buffered progress observation +
 * `pushEvent("next_chapter", { client_owned: true })`.
 *
 * Requires the canonical e2e fixture: chapter 1 has audio AND its next
 * chapter (chapter 2) also has audio, so the manual nav has a JS-side
 * target to swap to. `seed_e2e_book!/1` defaults to `audio_for: [1, 2, 3]`.
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader, showPill, BASE_URL } from "../helpers.js";

describe("Manual chapter nav (pill next button)", () => {
	let browser, page;

	before(async () => {
		({ browser, page } = await setup());

		// Walk to a chapter that has audio AND a next-chapter audio URL,
		// same probe loop the autoplay test uses.
		await openReader(page);
		const chapters = await page.evaluate(() => {
			const bar = document.getElementById("chapter-bar");
			return bar ? JSON.parse(bar.dataset.chapters) : [];
		});

		const bookId = page.url().match(/\/books\/(\d+)\/read/)?.[1];
		assert.ok(bookId, "openReader must land on a /books/:id/read/:cid URL");

		let found = false;
		for (const ch of chapters) {
			await page.goto(
				`${BASE_URL}/books/${bookId}/read/${ch.id}?nav=internal`,
				{ waitUntil: "domcontentloaded" },
			);
			await page.waitForSelector("[data-phx-session].phx-connected", {
				timeout: 10000,
			});
			await page.waitForSelector("#chapter-text", { timeout: 10000 });
			const player = await page
				.waitForSelector("#audio-player", { timeout: 1000 })
				.catch(() => null);
			if (player) {
				const nextUrl = await page.$eval(
					"#audio-player",
					(el) => el.dataset.nextAudioUrl || "",
				);
				if (nextUrl) {
					found = true;
					break;
				}
			}
		}
		assert.ok(
			found,
			"fixture must seed ≥2 contiguous audio-ready chapters; the manual " +
				"nav test needs both a current chapter and a next chapter with audio. " +
				"Check `audio_for` in ReadaloudAudiobook.Fixtures.E2E.seed!/1.",
		);
		// Wait for the hook to attach + audio.src to populate.
		await page.waitForFunction(
			() => {
				const a = document.getElementById("audio-element");
				return a?.src && a.src.length > 0;
			},
			{ timeout: 5000 },
		);
	});

	after(async () => {
		await teardown(browser);
	});

	it("pill next button uses JS.dispatch when audio is ready", async () => {
		// Server template should render the dispatch command, not a string
		// event name, when audio_state == :ready. Checking the rendered
		// phx-click attribute is the cheapest way to assert that branch.
		const phxClick = await page.$eval("#pill-next-chapter-btn", (el) =>
			el.getAttribute("phx-click"),
		);
		assert.ok(
			phxClick?.includes("audio:nav-next-chapter"),
			`pill next phx-click should be a JS.dispatch for audio:nav-next-chapter, got ${phxClick}`,
		);
	});

	it("clicking pill next swaps audio.src on the SAME <audio> node", async () => {
		// Mark the audio element so we can prove identity post-swap.
		// Use a JS expando (not an attribute) because morphdom strips
		// attrs not declared in the server template even on
		// phx-update="ignore" elements. The autoplay test uses the same
		// trick — see audio-autoplay.test.js for the rationale.
		await page.evaluate(() => {
			const a = document.getElementById("audio-element");
			if (a) a.__readaloudTestMarker = "pill-click-same-node";
		});

		const before = await page.evaluate(() => {
			const player = document.getElementById("audio-player");
			const audio = document.getElementById("audio-element");
			return {
				url: window.location.pathname + window.location.search,
				audioSrc: audio?.src ?? null,
				chapterId: player?.dataset.chapterId ?? null,
				nextAudioUrl: player?.dataset.nextAudioUrl ?? null,
				nextChapterId: player?.dataset.nextChapterId ?? null,
			};
		});
		assert.ok(before.nextChapterId, "must have a next chapter to swap to");

		// Show the pill and click the next button via puppeteer (real CDP
		// click, so LV's bubble-phase handler sees the same event the user
		// would generate).
		await showPill(page);
		await page.click("#pill-next-chapter-btn");

		// Wait for the JS swap + LV round-trip — both observable:
		// URL changes via history.pushState, audio.src changes via the
		// hook's window-event handler.
		await page.waitForFunction(
			(targetChapterId, oldAudioSrc) => {
				const url = window.location.pathname + window.location.search;
				const a = document.getElementById("audio-element");
				return (
					url.includes(`/read/${targetChapterId}`) &&
					a?.src &&
					a.src !== oldAudioSrc
				);
			},
			{ timeout: 5000 },
			before.nextChapterId,
			before.audioSrc,
		);

		const after = await page.evaluate(() => {
			const audio = document.getElementById("audio-element");
			return {
				url: window.location.pathname + window.location.search,
				audioSrc: audio?.src ?? null,
				marker: audio ? audio.__readaloudTestMarker : null,
			};
		});

		// SAME DOM node — proves we used the JS swap path (push_patch on
		// the LV server reload, not push_navigate which would replace the
		// element). This is the core regression assertion.
		assert.strictEqual(
			after.marker,
			"pill-click-same-node",
			"audio element must be the SAME node — re-creation would prove " +
				"we accidentally fell back to a path that tears down the player",
		);

		// URL is the next chapter.
		assert.ok(
			after.url.includes(`/read/${before.nextChapterId}`),
			`URL should be patched to /read/${before.nextChapterId}, got ${after.url}`,
		);

		// audio.src points at the next chapter's audio (or its prefetched
		// blob — both are valid; the autoplay test covers the blob path).
		const isBlob = after.audioSrc?.startsWith("blob:");
		if (!isBlob) {
			const expectedNetworkUrl = new URL(
				before.nextAudioUrl,
				BASE_URL,
			).toString();
			assert.strictEqual(
				after.audioSrc,
				expectedNetworkUrl,
				`audio.src should be next chapter URL after click, got ${after.audioSrc}`,
			);
		}
	});
});
