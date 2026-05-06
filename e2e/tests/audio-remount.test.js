/**
 * Audio player re-mount idempotency tests.
 *
 * Regression tests for the sleeping-mobile-wake bug: when the LiveView
 * WebSocket times out during a long phone sleep, the server-side LV
 * process is GC'd. On wake the client does a fresh mount with a new LV
 * process, which fires `destroyed` then `mounted` on every hook —
 * including the audio player.
 *
 * The <audio> element survives this cycle thanks to phx-update="ignore".
 * If the hook re-runs `audio.src = ...; audio.load()` on every mount,
 * it stomps the prefetched blob URL the user is currently listening to,
 * triggers a refetch from a still-suspended network, and strands the
 * user at 00:00/00:00 with a dead play button.
 *
 * The fix makes mount idempotent: skip the src reset if the audio
 * element already has a meaningful src. These tests pin that behavior.
 *
 * Requires the canonical e2e fixture: at least one chapter with audio
 * (default `audio_for: [1, 2]` in `ReadaloudAudiobook.Fixtures.E2E.seed!/1`).
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader, BASE_URL } from "../helpers.js";

describe("Audio player re-mount idempotency", () => {
	let browser, page;

	before(async () => {
		({ browser, page } = await setup());

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
				{ waitUntil: "networkidle2" },
			);
			await page.waitForSelector("[data-phx-session]", { timeout: 10000 });
			await page.waitForSelector("#chapter-text", { timeout: 10000 });
			const player = await page
				.waitForSelector("#audio-player", { timeout: 1000 })
				.catch(() => null);
			if (player) {
				found = true;
				break;
			}
		}
		assert.ok(
			found,
			"fixture must seed ≥1 audio-ready chapter; check `audio_for` " +
				"in ReadaloudAudiobook.Fixtures.E2E.seed!/1.",
		);
	});

	after(async () => {
		await teardown(browser);
	});

	it("audio.src is preserved when the hook is destroyed and re-mounted", async () => {
		// Wait for the initial mount to actually set audio.src.
		await page.waitForFunction(
			() => {
				const a = document.getElementById("audio-element");
				return a && a.src && a.src.includes("/api/books/");
			},
			{ timeout: 5000 },
		);

		// Replace the live audio src with a sentinel value. This stands in
		// for "user is mid-playback on a prefetched blob URL when the LV
		// times out" — what matters for the bug is that the src is some
		// non-empty value that the *server* did not put there.
		const sentinelSrc = `blob:${BASE_URL}/sentinel-${Date.now()}`;
		await page.evaluate((src) => {
			const a = document.getElementById("audio-element");
			a.src = src;
		}, sentinelSrc);

		const beforeSrc = await page.$eval("#audio-element", (el) => el.src);
		assert.strictEqual(beforeSrc, sentinelSrc, "sanity: sentinel applied");

		// Detach and re-attach the player div. Phoenix LV's MutationObserver
		// detects this and runs `destroyed` on removal followed by `mounted`
		// on insertion — the same lifecycle the bug triggers on a real
		// post-sleep reconnect with a dead server-side LV process.
		await page.evaluate(() => {
			const el = document.getElementById("audio-player");
			window.__remountSaved = {
				el,
				parent: el.parentNode,
				nextSibling: el.nextSibling,
			};
			el.remove();
		});

		// Wait for the MutationObserver to actually flush the removal —
		// observable as #audio-player being gone from the DOM. Without this
		// gap, destroy and mount can collapse into a single flush and
		// short-circuit the lifecycle we're trying to exercise.
		await page.waitForFunction(
			() => document.getElementById("audio-player") === null,
			{ timeout: 1000 },
		);

		await page.evaluate(() => {
			const { el, parent, nextSibling } = window.__remountSaved;
			parent.insertBefore(el, nextSibling);
			delete window.__remountSaved;
		});

		// Wait for the re-mount to complete — the audio-player div is back.
		await page.waitForSelector("#audio-player", { timeout: 5000 });

		const afterSrc = await page.$eval("#audio-element", (el) => el.src);
		assert.strictEqual(
			afterSrc,
			sentinelSrc,
			"audio.src must survive a hook destroy/mount cycle — without " +
				"this, sleeping-mobile autoplay re-stalls on wake when LV " +
				"reconnects with a fresh process",
		);
	});

	it("audio.currentTime is preserved across destroy/mount (proves load() was not called)", async () => {
		// Restore real audio src (previous test left a sentinel) and wait
		// for metadata so we have a valid duration to seek into.
		await page.evaluate(() => {
			const a = document.getElementById("audio-element");
			const player = document.getElementById("audio-player");
			a.src = player.dataset.audioUrl;
			a.load();
		});
		await page.waitForFunction(
			() => {
				const a = document.getElementById("audio-element");
				return a && Number.isFinite(a.duration) && a.duration > 0;
			},
			{ timeout: 10000 },
		);

		// Seek to a distinctive non-zero time. The OLD code's destroy →
		// mount cycle called `audio.src = url; audio.load()` on mount,
		// and load() resets currentTime to 0. The NEW code skips that
		// when src is already set, so currentTime survives.
		const SEEK_SECONDS = 7.5;
		await page.evaluate((t) => {
			const a = document.getElementById("audio-element");
			a.currentTime = t;
		}, SEEK_SECONDS);
		// `currentTime =` is synchronous on the element, but the seeking
		// state takes a frame to settle. Wait for the seek to commit.
		await page.waitForFunction(
			(target) => {
				const a = document.getElementById("audio-element");
				return a && Math.abs(a.currentTime - target) < 1;
			},
			{ timeout: 2000 },
			SEEK_SECONDS,
		);

		const beforeTime = await page.$eval(
			"#audio-element",
			(el) => el.currentTime,
		);
		assert.ok(
			Math.abs(beforeTime - SEEK_SECONDS) < 1,
			`sanity: currentTime should be near ${SEEK_SECONDS}, got ${beforeTime}`,
		);

		// Re-mount cycle.
		await page.evaluate(() => {
			const el = document.getElementById("audio-player");
			window.__remountSaved = {
				el,
				parent: el.parentNode,
				nextSibling: el.nextSibling,
			};
			el.remove();
		});
		await page.waitForFunction(
			() => document.getElementById("audio-player") === null,
			{ timeout: 1000 },
		);
		await page.evaluate(() => {
			const { el, parent, nextSibling } = window.__remountSaved;
			parent.insertBefore(el, nextSibling);
			delete window.__remountSaved;
		});
		await page.waitForSelector("#audio-player", { timeout: 5000 });

		const afterTime = await page.$eval(
			"#audio-element",
			(el) => el.currentTime,
		);
		// audio.load() resets currentTime to 0; if the hook called it on
		// mount (the regression), this drops to ~0. Allow a small window
		// for natural drift if the audio happened to be playing.
		assert.ok(
			Math.abs(afterTime - SEEK_SECONDS) < 1.5,
			`currentTime should survive re-mount (was ${beforeTime}, now ${afterTime}). ` +
				`If this drops to ~0, the hook is calling audio.load() on re-mount, ` +
				`which is the sleeping-mobile-wake regression.`,
		);
	});

	it("the mount-time idempotency heuristic accepts blob: and network URLs", async () => {
		// This is a documentation-of-contract test. The hook decides
		// "should I reset audio.src on mount?" based on whether the
		// existing src is meaningful. If you change the heuristic in
		// audio_player.ts, update this test too — and think hard about
		// whether the change breaks the sleeping-mobile-wake invariant.
		const verdicts = await page.evaluate(() => {
			const a = document.createElement("audio");
			const samples = [
				"",
				window.location.href,
				`${window.location.origin}/`,
				"http://example.com/audio.wav",
				"blob:http://localhost/abc-123",
				`${window.location.origin}/api/books/2/chapters/3/audio`,
			];
			return samples.map((src) => {
				a.src = src;
				const real = a.src;
				const meaningful =
					real !== "" &&
					real !== window.location.href &&
					real !== `${window.location.origin}/`;
				return { setSrc: src, realSrc: real, meaningful };
			});
		});

		// Empty / page-URL fallbacks → not meaningful, mount should reset.
		assert.strictEqual(verdicts[0].meaningful, false, "empty src");
		assert.strictEqual(verdicts[1].meaningful, false, "page URL src");
		assert.strictEqual(verdicts[2].meaningful, false, "origin/ src");
		// Real URLs → meaningful, mount should leave alone.
		assert.strictEqual(verdicts[3].meaningful, true, "external URL");
		assert.strictEqual(verdicts[4].meaningful, true, "blob: URL");
		assert.strictEqual(verdicts[5].meaningful, true, "same-origin api URL");
	});
});
