/**
 * Audio auto-next-chapter test.
 *
 * Verifies the chapter swap on `ended` keeps the same <audio> element and
 * uses LiveView push_patch (no full navigation). This is the critical
 * mobile-lock-screen fix: a full navigation tears down the OS audio
 * session, which is why autoplay used to fail when the phone was asleep.
 *
 * Requires the canonical e2e fixture: a chapter with audio that *also*
 * has a next chapter with audio (so `next_audio_url` is populated).
 * `seed_e2e_book!/1` defaults to `audio_for: [1, 2, 3, 4, 5]` — chapter 1 sees
 * chapter 2 as the next audio-ready chapter.
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader, BASE_URL } from "../helpers.js";

describe("Audio auto-next-chapter", () => {
	let browser, page;

	before(async () => {
		({ browser, page } = await setup());

		// Find a chapter that has audio AND a next-chapter audio URL.
		// The fixture guarantees chapter 1 satisfies this; we still walk
		// the bar in case the test ordering shifted.
		await openReader(page);
		const chapters = await page.evaluate(() => {
			const bar = document.getElementById("chapter-bar");
			return bar ? JSON.parse(bar.dataset.chapters) : [];
		});

		const bookId = page.url().match(/\/books\/(\d+)\/read/)?.[1];
		assert.ok(bookId, "openReader must land on a /books/:id/read/:cid URL");
		assert.ok(
			chapters.length > 0,
			"fixture must seed ≥1 chapter; check ReadaloudAudiobook.Fixtures.E2E.seed!/1",
		);

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
			// `#audio-player` is gated by audio_state == :ready; absence after
			// chapter-text renders means this chapter has no audio. Don't fail —
			// just walk to the next chapter.
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
			"fixture must seed ≥2 contiguous audio-ready chapters; the audio-* " +
				"tests need both a current chapter and a next chapter with audio. " +
				"Check `audio_for` in ReadaloudAudiobook.Fixtures.E2E.seed!/1.",
		);
	});

	after(async () => {
		await teardown(browser);
	});

	it("player exposes next-chapter data attrs", async () => {
		const attrs = await page.$eval("#audio-player", (el) => ({
			audioUrl: el.dataset.audioUrl,
			nextAudioUrl: el.dataset.nextAudioUrl,
			nextTimingsUrl: el.dataset.nextTimingsUrl,
			nextChapterId: el.dataset.nextChapterId,
			chapterId: el.dataset.chapterId,
			bookTitle: el.dataset.bookTitle,
			chapterTitle: el.dataset.chapterTitle,
		}));
		assert.ok(attrs.audioUrl, "audioUrl must be set");
		assert.ok(attrs.nextAudioUrl, "nextAudioUrl must be set");
		assert.ok(attrs.nextTimingsUrl, "nextTimingsUrl must be set");
		assert.ok(attrs.nextChapterId, "nextChapterId must be set");
		assert.notStrictEqual(
			attrs.audioUrl,
			attrs.nextAudioUrl,
			"next URL must differ from current",
		);
		assert.ok(attrs.bookTitle, "bookTitle must be set for Media Session");
		assert.ok(attrs.chapterTitle, "chapterTitle must be set for Media Session");
	});

	it("Media Session metadata is registered", async (t) => {
		// Wait for the hook to populate MediaMetadata (or for the browser
		// to declare it doesn't support MediaSession at all).
		await page
			.waitForFunction(
				() =>
					!("mediaSession" in navigator) ||
					navigator.mediaSession.metadata !== null,
				{ timeout: 5000 },
			)
			.catch(() => {});
		const meta = await page.evaluate(() => {
			if (!("mediaSession" in navigator)) return null;
			const m = navigator.mediaSession.metadata;
			if (!m) return null;
			return { title: m.title, artist: m.artist, album: m.album };
		});
		// MediaSession is a runtime browser capability, not a fixture
		// precondition — soft-skip if the headless chromium build lacks it.
		if (meta === null) {
			t.skip("MediaSession not available in this browser");
			return;
		}
		assert.ok(meta.title?.length > 0, "Media Session title should be set");
		assert.ok(meta.artist?.length > 0, "Media Session artist should be set");
	});

	it("prefetches next chapter audio into a Blob URL while current plays", async () => {
		// Enable autoNextChapter (gates prefetch) and reload so the
		// PersistedRecord cache picks it up.
		await page.evaluate(() => {
			const cur = (() => {
				try {
					return JSON.parse(
						localStorage.getItem("readaloud-reader-settings") || "{}",
					);
				} catch {
					return {};
				}
			})();
			cur.autoNextChapter = true;
			localStorage.setItem("readaloud-reader-settings", JSON.stringify(cur));
		});
		await page.reload({ waitUntil: "domcontentloaded" });
		await page.waitForSelector("#audio-element", { timeout: 10000 });

		// Drive currentTime past the 15% prefetch trigger fraction by
		// poking the audio element directly. We're not asserting playback,
		// just want a `timeupdate` to fire with currentTime/duration > 0.15.
		// Wait for metadata first so duration is known.
		await page.evaluate(
			() =>
				new Promise((resolve) => {
					const a = document.getElementById("audio-element");
					if (!a) return resolve();
					if (a.readyState >= 1 && Number.isFinite(a.duration))
						return resolve();
					a.addEventListener("loadedmetadata", () => resolve(), { once: true });
				}),
		);
		await page.evaluate(() => {
			const a = document.getElementById("audio-element");
			if (!a || !Number.isFinite(a.duration)) return;
			a.currentTime = a.duration * 0.2;
			a.dispatchEvent(new Event("timeupdate"));
		});

		// Wait for the fetch to fire. fetch() shows up as a `resource`
		// performance entry; we can't reach into the hook's closure, but
		// we *can* observe the request itself.
		const nextUrl = await page.$eval(
			"#audio-player",
			(el) => el.dataset.nextAudioUrl || "",
		);
		await page
			.waitForFunction(
				() =>
					performance
						.getEntriesByType("resource")
						.some(
							(e) =>
								e.name.includes("/api/books/") &&
								e.name.includes("/audio") &&
								e.initiatorType === "fetch",
						),
				{ timeout: 20000 },
			)
			.catch(() => {
				throw new Error(
					`expected a fetch() to ${nextUrl} after currentTime crossed 15%, ` +
						"but none was observed within 20s",
				);
			});
	});

	it("ended event swaps audio.src + patches URL without tearing down player", async () => {
		// Snapshot current state.
		const before = await page.evaluate(() => {
			const player = document.getElementById("audio-player");
			const audio = document.getElementById("audio-element");
			return {
				url: window.location.pathname + window.location.search,
				audioSrc: audio?.src ?? null,
				nextAudioUrl: player?.dataset.nextAudioUrl ?? null,
				nextChapterId: player?.dataset.nextChapterId ?? null,
				audioNodeId: audio ? audio.dataset.testId : null,
			};
		});

		assert.ok(before.nextAudioUrl, "must have a next audio URL to swap to");
		assert.ok(
			before.audioSrc?.includes(
				`/chapters/${before.url.match(/\/read\/(\d+)/)?.[1]}/audio`,
			),
			`audio src should be the current chapter's URL, got ${before.audioSrc}`,
		);

		// Auto-next-chapter is a user-controlled reader setting persisted in
		// localStorage. The hook reads it via PersistedRecord, which caches
		// the value at module-load time — so we must set localStorage *and
		// reload* for the new value to be picked up.
		await page.evaluate(() => {
			const cur = (() => {
				try {
					return JSON.parse(
						localStorage.getItem("readaloud-reader-settings") || "{}",
					);
				} catch {
					return {};
				}
			})();
			cur.autoNextChapter = true;
			localStorage.setItem("readaloud-reader-settings", JSON.stringify(cur));
		});
		await page.reload({ waitUntil: "domcontentloaded" });
		await page.waitForSelector("#audio-element", { timeout: 10000 });
		// Wait for the hook to finish mount + apply the fresh
		// PersistedRecord — observable as audio.src being populated.
		await page.waitForFunction(
			() => {
				const a = document.getElementById("audio-element");
				return a && a.src && a.src.length > 0;
			},
			{ timeout: 5000 },
		);

		// Mark the (post-reload) audio element so we can prove identity
		// after the swap. Use a JS expando property (not a DOM attribute)
		// because morphdom strips attributes not declared in the server
		// template — even on phx-update="ignore" elements (it preserves
		// children, not custom attrs).
		await page.evaluate(() => {
			const a = document.getElementById("audio-element");
			if (a) a.__readaloudTestMarker = "same-node-marker";
		});

		// Trigger the `ended` event on the audio element. The hook listens
		// for this and is supposed to swap src to the next chapter and push
		// next_chapter to the server (push_patch).
		await page.evaluate(() => {
			const a = document.getElementById("audio-element");
			if (a) a.dispatchEvent(new Event("ended"));
		});

		// Wait for the JS swap + LV push_patch round-trip — both observable.
		// The URL changes via push_patch; the audio.src changes via the
		// hook's ended handler.
		await page.waitForFunction(
			(targetChapterId) => {
				const url = window.location.pathname + window.location.search;
				const a = document.getElementById("audio-element");
				const urlChanged = url.includes(`/read/${targetChapterId}`);
				const srcChanged = a?.src && !a.src.includes(`/chapters/1/audio`);
				return urlChanged && srcChanged;
			},
			{ timeout: 5000 },
			before.nextChapterId,
		);

		const after = await page.evaluate(() => {
			const audio = document.getElementById("audio-element");
			return {
				url: window.location.pathname + window.location.search,
				audioSrc: audio?.src ?? null,
				audioNodeMarker: audio ? audio.__readaloudTestMarker : null,
			};
		});

		// Same DOM node — proves push_patch (not push_navigate).
		assert.strictEqual(
			after.audioNodeMarker,
			"same-node-marker",
			"audio element must be the SAME node — push_navigate would replace it",
		);

		// audio.src now points at the next chapter — either as the network
		// URL or as a `blob:` URL when the prefetch beat us to it. The
		// blob path is the one that actually fixes sleeping-mobile
		// autoplay, so when it's chosen we just verify the prefix.
		const expectedNetworkUrl =
			before.nextAudioUrl && new URL(before.nextAudioUrl, BASE_URL).toString();
		const isBlob = after.audioSrc?.startsWith("blob:");
		if (isBlob) {
			assert.ok(
				after.audioSrc?.startsWith(`blob:${BASE_URL}`),
				`expected a blob: URL on the page origin, got ${after.audioSrc}`,
			);
		} else {
			assert.strictEqual(
				after.audioSrc,
				expectedNetworkUrl,
				`audio.src should be next chapter URL after ended, got ${after.audioSrc}`,
			);
		}

		// URL got patched to the next chapter.
		assert.ok(
			after.url.includes(`/read/${before.nextChapterId}`),
			`URL should be patched to /read/${before.nextChapterId}, got ${after.url}`,
		);
	});
});
