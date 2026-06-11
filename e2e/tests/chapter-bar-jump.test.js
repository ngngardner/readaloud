/**
 * Chapter-bar jump during audio playback.
 *
 * Regression for the server-owned-nav half of the chapter-state split:
 * jumping via the chapter bar pushes `jump_to_chapter`, the server
 * push_patches, morphdom updates the reader text and the player's
 * data-* attrs — but nothing used to swap the `<audio>` element
 * (preserved via phx-update="ignore"), so it kept playing the OLD
 * chapter under the NEW chapter's text and progress writes paired the
 * new chapter id with the old audio position.
 *
 * The fix is the AudioPlayerHook's dataset reconciler
 * (syncAudioToDataset): on every LV update it compares the dataset's
 * chapter against what the audio element actually has loaded and swaps
 * to follow — same <audio> node, play/pause state preserved. This test
 * pins that: jump via a chapter-bar pill, assert audio.src follows on
 * the SAME node.
 *
 * Requires the canonical e2e fixture: chapter 1 has audio AND chapter 2
 * has audio (`seed_e2e_book!/1` defaults to `audio_for: [1, 2]`), so the
 * jump target's audio URL exists for the reconciler to load.
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader, showPill, BASE_URL } from "../helpers.js";

describe("Chapter-bar jump during playback", () => {
	let browser, page;

	before(async () => {
		({ browser, page } = await setup());

		// Walk to a chapter that has audio AND a next audio chapter, same
		// probe loop as the other audio-* tests.
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
			"fixture must seed ≥2 contiguous audio-ready chapters; the " +
				"chapter-bar jump test needs a current chapter and a jump target " +
				"with audio. Check `audio_for` in ReadaloudAudiobook.Fixtures.E2E.seed!/1.",
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

	it("jump via chapter-bar pill swaps audio.src on the SAME <audio> node", async () => {
		// Identity marker — JS expando, not an attribute, because morphdom
		// strips runtime attrs even on phx-update="ignore" elements.
		await page.evaluate(() => {
			const a = document.getElementById("audio-element");
			if (a) a.__readaloudTestMarker = "bar-jump-same-node";
		});

		// Try to start playback so the reconciler's state-preserving swap
		// is exercised; autoplay policy may block it, in which case the
		// swap-only assertions still hold (paused swap stays paused).
		await page.click("#play-pause-btn");
		const wasPlaying = await page
			.waitForFunction(
				() => {
					const a = document.getElementById("audio-element");
					return !!a && !a.paused;
				},
				{ timeout: 3000 },
			)
			.then(() => true)
			.catch(() => false);

		const before = await page.evaluate(() => {
			const player = document.getElementById("audio-player");
			const bar = document.getElementById("chapter-bar");
			const chapters = bar ? JSON.parse(bar.dataset.chapters) : [];
			const targetId = player?.dataset.nextChapterId ?? null;
			return {
				audioSrc: document.getElementById("audio-element")?.src ?? null,
				targetId,
				targetIdx: chapters.findIndex((c) => String(c.id) === targetId),
			};
		});
		assert.ok(before.targetId, "must have a next audio chapter to jump to");
		assert.ok(
			before.targetIdx >= 0,
			"jump target must be present in the chapter bar",
		);

		// Open the chapter bar (pill → indicator toggles it) and click the
		// target chapter's pill — the same server-owned jump_to_chapter
		// path a user scrubbing the bar takes.
		await showPill(page);
		await page.click("#chapter-indicator");
		// The bar opens with a 200ms scaleY transition — wait for it to be
		// open and settled, or the pill click can land mid-animation on
		// shifting coordinates.
		await page.waitForFunction(
			() =>
				document
					.getElementById("chapter-bar")
					?.classList.contains("scale-y-100"),
			{ timeout: 3000 },
		);
		await new Promise((resolve) => setTimeout(resolve, 250));
		await page.click(`[data-chapter-pill="${before.targetIdx}"]`);

		// URL patches via the LV diff; audio follows via the reconciler.
		await page.waitForFunction(
			(targetId, oldSrc) => {
				const a = document.getElementById("audio-element");
				return (
					window.location.pathname.includes(`/read/${targetId}`) &&
					a?.src &&
					a.src !== oldSrc &&
					a.src.includes(`/chapters/${targetId}/audio`)
				);
			},
			{ timeout: 5000 },
			before.targetId,
			before.audioSrc,
		);

		const after = await page.evaluate(() => {
			const a = document.getElementById("audio-element");
			const player = document.getElementById("audio-player");
			return {
				marker: a ? a.__readaloudTestMarker : null,
				paused: a?.paused ?? null,
				datasetChapterId: player?.dataset.chapterId ?? null,
			};
		});

		// SAME node — the reconciler swaps src in place; a re-created
		// element would mean the player was torn down (OS audio session
		// lost on mobile).
		assert.strictEqual(
			after.marker,
			"bar-jump-same-node",
			"audio element must be the SAME node after a chapter-bar jump",
		);

		// The LV landed on the target chapter (dataset follows assigns).
		assert.strictEqual(
			after.datasetChapterId,
			before.targetId,
			"player dataset should be on the jump target",
		);

		// Play/pause state is preserved across the reconciler swap. Poll —
		// the swap's play() resumes asynchronously after the new src loads.
		if (wasPlaying) {
			await page
				.waitForFunction(
					() => {
						const a = document.getElementById("audio-element");
						return !!a && !a.paused;
					},
					{ timeout: 5000 },
				)
				.catch(() => {
					assert.fail(
						"audio that was playing before the jump should keep playing",
					);
				});
		}
	});
});
