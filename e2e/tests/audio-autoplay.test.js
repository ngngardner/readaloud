/**
 * Audio auto-next-chapter test.
 *
 * Verifies the chapter swap on `ended` keeps the same <audio> element and
 * uses LiveView push_patch (no full navigation). This is the critical
 * mobile-lock-screen fix: a full navigation tears down the OS audio
 * session, which is why autoplay used to fail when the phone was asleep.
 *
 * Skipped automatically if the test book has no audio-ready chapter
 * (e.g. the NixOS VM smoke environment, which seeds chapters without
 * generated audio).
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader, sleep, BASE_URL } from "../helpers.js";

describe("Audio auto-next-chapter", () => {
	let browser, page;
	let playerExists = false;

	before(async () => {
		({ browser, page } = await setup());

		// Find a chapter that actually has audio. We don't know the exact id,
		// so walk chapters from the book and stop at the first one whose
		// reader page renders the #audio-player element.
		await openReader(page);
		const chapters = await page.evaluate(() => {
			const bar = document.getElementById("chapter-bar");
			return bar ? JSON.parse(bar.dataset.chapters) : [];
		});

		const bookId = page.url().match(/\/books\/(\d+)\/read/)?.[1];
		if (!bookId || chapters.length === 0) return;

		for (const ch of chapters) {
			await page.goto(
				`${BASE_URL}/books/${bookId}/read/${ch.id}?nav=internal`,
				{ waitUntil: "networkidle2" },
			);
			await page.waitForSelector("[data-phx-session]", { timeout: 10000 });
			await sleep(300);
			const player = await page.$("#audio-player");
			if (player) {
				const nextUrl = await page.$eval(
					"#audio-player",
					(el) => el.dataset.nextAudioUrl || "",
				);
				if (nextUrl) {
					playerExists = true;
					break;
				}
			}
		}
	});

	after(async () => {
		await teardown(browser);
	});

	it("player exposes next-chapter data attrs", async (t) => {
		if (!playerExists) {
			t.skip("No audio-ready chapter with a next chapter — skipping");
			return;
		}
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
		if (!playerExists) {
			t.skip("No audio-ready chapter — skipping");
			return;
		}
		// Wait a tick for the hook to mount and call new MediaMetadata().
		await sleep(200);
		const meta = await page.evaluate(() => {
			if (!("mediaSession" in navigator)) return null;
			const m = navigator.mediaSession.metadata;
			if (!m) return null;
			return { title: m.title, artist: m.artist, album: m.album };
		});
		// Headless Chromium supports MediaSession; if it doesn't on a given
		// runtime, treat as a soft skip rather than a hard failure.
		if (meta === null) {
			t.skip("MediaSession not available in this browser");
			return;
		}
		assert.ok(meta.title?.length > 0, "Media Session title should be set");
		assert.ok(meta.artist?.length > 0, "Media Session artist should be set");
	});

	it("prefetches next chapter audio into a Blob URL while current plays", async (t) => {
		if (!playerExists) {
			t.skip("No audio-ready chapter — skipping");
			return;
		}

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
		await page.reload({ waitUntil: "networkidle2" });
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

		// Wait for the fetch + blob URL to materialize. WAV files can be
		// large; give it some time on a slow machine.
		const nextUrl = await page.$eval(
			"#audio-player",
			(el) => el.dataset.nextAudioUrl || "",
		);
		const start = Date.now();
		let prefetched = false;
		while (Date.now() - start < 20000) {
			const found = await page.evaluate(() => {
				// Look at performance entries — fetch() shows up as a
				// resource entry. We can't reach into the hook's closure,
				// but we *can* see if a request to the next-chapter audio
				// URL has been issued.
				return performance
					.getEntriesByType("resource")
					.some(
						(e) =>
							e.name.includes("/api/books/") &&
							e.name.includes("/audio") &&
							e.initiatorType === "fetch",
					);
			});
			if (found) {
				prefetched = true;
				break;
			}
			await sleep(500);
		}
		assert.ok(
			prefetched,
			`expected a fetch() to ${nextUrl} after currentTime crossed 15%, but none was observed`,
		);
	});

	it("ended event swaps audio.src + patches URL without tearing down player", async (t) => {
		if (!playerExists) {
			t.skip("No audio-ready chapter — skipping");
			return;
		}

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
		await page.reload({ waitUntil: "networkidle2" });
		await page.waitForSelector("#audio-element", { timeout: 10000 });
		await sleep(300);

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

		// Wait for the JS swap + LV push_patch round-trip.
		await sleep(2000);

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

		// audio.src now points at the next chapter.
		assert.strictEqual(
			after.audioSrc,
			before.nextAudioUrl && new URL(before.nextAudioUrl, BASE_URL).toString(),
			`audio.src should be next chapter URL after ended, got ${after.audioSrc}`,
		);

		// URL got patched to the next chapter.
		assert.ok(
			after.url.includes(`/read/${before.nextChapterId}`),
			`URL should be patched to /read/${before.nextChapterId}, got ${after.url}`,
		);
	});
});
