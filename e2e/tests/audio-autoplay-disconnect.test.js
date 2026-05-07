/**
 * Autoplay regression: LV WebSocket disconnect during chapter boundary.
 *
 * Reproduces the mobile-screen-locked bug Noah hit in production:
 *
 *   - Listening on chapter N. Phone screen locks. The OS keeps the
 *     <audio> element playing via the Media Session, but the LV
 *     WebSocket is suspended/torn down.
 *   - Audio plays to the end of N. The hook's `ended` listener fires
 *     and JS-side swaps audio.src to chapter N+1 (using the prefetched
 *     blob). audio.play() succeeds — playback continues briefly into
 *     N+1 over the lock screen.
 *   - The hook ALSO calls `pushEvent("next_chapter")` so the server
 *     can push_patch the URL. With the socket dead, that event is
 *     dropped on the floor.
 *   - User wakes the phone. LV reconnects with a fresh process and
 *     re-mounts on the URL it sees, which is still chapter N. The
 *     audio element survives (phx-update="ignore") and audio.src is
 *     still chapter N+1's blob. State is now permanently inconsistent:
 *     URL says N, audio plays N+1, and the user has to refresh and
 *     manually navigate to N+1 to recover.
 *
 * Invariant this test pins: after `ended` + autoplay, however the LV
 * socket behaves around the chapter boundary, the URL must eventually
 * agree with the chapter audio.src points at. Either push_patch lands
 * (the desired fix), or audio.src reverts to match the URL — but the
 * two must NOT diverge permanently.
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader, BASE_URL } from "../helpers.js";

describe("Audio autoplay across LV disconnect", () => {
	let browser, page;

	before(async () => {
		({ browser, page } = await setup());

		// Walk to the first chapter that has both audio AND a next-audio
		// chapter (same precondition as audio-autoplay.test.js).
		await openReader(page);
		const chapters = await page.evaluate(() => {
			const bar = document.getElementById("chapter-bar");
			return bar ? JSON.parse(bar.dataset.chapters) : [];
		});
		const bookId = page.url().match(/\/books\/(\d+)\/read/)?.[1];
		assert.ok(bookId, "openReader must land on a /books/:id/read/:cid URL");
		assert.ok(chapters.length > 0, "fixture must seed ≥1 chapter");

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
			"fixture must seed ≥2 contiguous audio-ready chapters; check " +
				"`audio_for` in ReadaloudAudiobook.Fixtures.E2E.seed!/1.",
		);

		// Enable autoplay and reload so the hook's PersistedRecord cache
		// picks up the new value on its next mount.
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
		// Wait for the hook to apply its initial src so we have something
		// to swap away from.
		await page.waitForFunction(
			() => {
				const a = document.getElementById("audio-element");
				return a?.src && a.src.includes("/api/books/");
			},
			{ timeout: 5000 },
		);
	});

	after(async () => {
		await teardown(browser);
	});

	it("browser URL updates to next chapter immediately, even with the LV socket dead", async () => {
		// This is the invariant we want from the fix: the URL must change
		// client-side as part of the swap, not contingent on a server
		// roundtrip. The original code only updates the URL via
		// `push_patch` (server-side), which means a screen-locked phone
		// whose LV diff doesn't make it back to the browser leaves the
		// URL pinned at the previous chapter while audio plays the next
		// one — exactly the user-visible bug from prod logs.
		//
		// We test the invariant directly by killing the socket and NOT
		// reconnecting it. If the URL only updates via `push_patch`, this
		// test fails. If the swap also updates the URL via History API
		// (or LV's own JS-side patch), it passes regardless of socket
		// state.

		const before = await page.evaluate(() => {
			const player = document.getElementById("audio-player");
			return {
				url: window.location.pathname,
				chapterId: player?.dataset.chapterId,
				nextChapterId: player?.dataset.nextChapterId,
			};
		});
		assert.ok(before.nextChapterId, "must have a next chapter to swap to");
		assert.notStrictEqual(
			before.chapterId,
			before.nextChapterId,
			"sanity: next chapter id must differ from current",
		);

		// Kill the LV socket and disable reconnect so any pushEvent the
		// hook fires goes nowhere — like a phone whose WebSocket is
		// suspended and whose server-side LV process eventually times out.
		// Phoenix's Channel buffers events while the socket is briefly
		// down and flushes on rejoin; the user-visible bug is the case
		// where the socket *doesn't* come back in time and the buffered
		// event is lost. We model that here as "no reconnect at all."
		await page.evaluate(() => {
			// `liveSocket.disconnect()` closes the socket; without
			// `connect()` it stays closed. We also override `connect()`
			// to a no-op so any internal Phoenix reconnect logic can't
			// silently bring it back during the test window.
			window.liveSocket.disconnect();
			window.liveSocket.connect = () => {};
		});
		await page.waitForFunction(() => !window.liveSocket.isConnected(), {
			timeout: 5000,
		});

		// Audio finishes the current chapter. Hook fires its `ended`
		// listener, swaps audio.src JS-side, and pushEvent("next_chapter")
		// goes into the void.
		await page.evaluate(() => {
			const a = document.getElementById("audio-element");
			a.dispatchEvent(new Event("ended"));
		});

		// Sanity: the JS-side swap fired (audio.src changed). If this
		// fails the test isn't reaching the code path under test.
		await page.waitForFunction(
			(currentChapterId) => {
				const a = document.getElementById("audio-element");
				if (!a?.src) return false;
				return !a.src.endsWith(`/chapters/${currentChapterId}/audio`);
			},
			{ timeout: 3000 },
			before.chapterId,
		);

		// THE INVARIANT: with the socket dead and no reconnect, the URL
		// must still advance to the next chapter within a reasonable
		// window. If the URL only updates via server push_patch, this
		// times out → test fails RED → fix needs to add a client-side
		// URL update at swap time.
		const urlAdvanced = await page
			.waitForFunction(
				(targetChapterId) => {
					const m = window.location.pathname.match(/\/read\/(\d+)/);
					return m?.[1] === targetChapterId;
				},
				{ timeout: 3000 },
				before.nextChapterId,
			)
			.then(() => true)
			.catch(() => false);

		const after = await page.evaluate(() => {
			const a = document.getElementById("audio-element");
			return {
				url: window.location.pathname,
				audioSrc: a?.src ?? null,
				socketConnected: window.liveSocket.isConnected(),
			};
		});

		assert.strictEqual(
			after.socketConnected,
			false,
			"sanity: socket must still be disconnected during the assertion",
		);

		assert.ok(
			urlAdvanced,
			"Browser URL did not advance to the next chapter while the LV " +
				"socket was dead.\n" +
				`  url:               ${after.url}\n` +
				`  audio.src:         ${after.audioSrc}\n` +
				`  expected chapter:  ${before.nextChapterId}\n` +
				`  was on chapter:    ${before.chapterId}\n\n` +
				"This is the mobile-lock-screen autoplay bug. Audio swaps to " +
				"the next chapter JS-side; the URL only updates via server " +
				"push_patch. When the WebSocket is suspended (phone locked) " +
				"and the server-side LV process times out before its diff is " +
				"delivered, the patch never lands. The user comes back to a " +
				"player whose audio is on chapter N+1 but whose URL is N — " +
				"so a refresh sends them back to N. The fix is to update the " +
				"URL client-side (history.pushState or the LV JS patch API) " +
				"as part of the swap, so the URL doesn't depend on the WS.",
		);
	});
});
