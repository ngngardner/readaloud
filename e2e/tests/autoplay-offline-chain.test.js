/**
 * Autoplay chain across TWO offline chapter boundaries + recovery.
 *
 * audio-autoplay-disconnect.test.js pins the FIRST boundary: with the LV
 * socket dead, `ended` still swaps audio.src and pushState's the URL.
 * This file pins what the 2026-06-11 commute incident showed happens at
 * the SECOND boundary:
 *
 *   - Chapter N ends offline; the hook swaps to N+1's prefetched blob.
 *     The server never delivers a dataset refresh (WS is dead), so the
 *     dataset still describes chapter N — whose "next" is N+1.
 *   - Chapter N+1 ends. Pre-fix, the hook read its nav target from the
 *     stale dataset and "advanced" to N+1 — the chapter that just
 *     finished — restarting it at 0:00 over a network URL with no
 *     network (NETWORK_NO_SOURCE) and clobbering the position cache.
 *   - The network came back 16s later, but nothing ever looked at the
 *     paused element again. Playback stayed dead for the rest of the
 *     commute.
 *
 * The fix: the prefetch bundle also fetches /nav for the next chapter,
 * so by the time N+1 plays, its own neighbors are client-local
 * (CHAPTER_WINDOW). A self-swap guard refuses targets equal to the
 * loaded chapter, and a pending-autoplay intent retries the failed swap
 * when connectivity returns.
 *
 * Requires the canonical fixture's three consecutive audio-ready
 * chapters (`audio_for: [1, 2, 3]`).
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { existsSync, renameSync } from "node:fs";
import { setup, teardown, openReader, BASE_URL } from "../helpers.js";

describe("Autoplay across two offline chapter boundaries", () => {
	let browser, page;
	/** Every console line the page emits; the hook's log() mirrors all
	 * player events to console.log("[autoplay <ts>] <event>", {...}). */
	const consoleLines = [];
	const sawLog = (event) =>
		consoleLines.some((line) => line.includes(`] ${event}`));
	const waitForLog = async (event, timeoutMs = 5000) => {
		const deadline = Date.now() + timeoutMs;
		while (Date.now() < deadline) {
			if (sawLog(event)) return;
			await new Promise((r) => setTimeout(r, 100));
		}
		throw new Error(
			`expected console log event "${event}" within ${timeoutMs}ms`,
		);
	};

	let bookId;
	let ch1, ch2, ch3; // chapter ids (strings), all audio-ready

	// Making the ch3 media load FAIL while "offline" needs two mechanisms:
	//
	//   * page.setOfflineMode — drives navigator.onLine and the
	//     online/offline events the hook's recovery listens to. On desktop
	//     chrome it also blocks media loads, but in the e2e VM chromium
	//     MEDIA-element requests bypass CDP network emulation entirely
	//     (and Fetch interception — verified empirically: the request
	//     never reaches an interception handler and loads fine).
	//   * hiding the fixture WAV on disk — fails the load server-side
	//     (send_file 500s), which no client network stack can route
	//     around. The VM passes the file path as AUDIO_FIXTURE_FILE (the
	//     suite runs as root); local runs may omit it since emulation
	//     blocks media there anyway.
	const fixtureFile = process.env.AUDIO_FIXTURE_FILE || null;
	const hiddenFile = fixtureFile ? `${fixtureFile}.hidden` : null;
	const hideAudioFile = () => {
		if (fixtureFile && existsSync(fixtureFile)) {
			renameSync(fixtureFile, hiddenFile);
		}
	};
	const restoreAudioFile = () => {
		if (hiddenFile && existsSync(hiddenFile)) {
			renameSync(hiddenFile, fixtureFile);
		}
	};

	before(async () => {
		({ browser, page } = await setup());
		page.on("console", (msg) => consoleLines.push(msg.text()));

		// Walk to a chapter with audio AND a next-audio chapter (same
		// precondition walk as audio-autoplay.test.js).
		await openReader(page);
		const chapters = await page.evaluate(() => {
			const bar = document.getElementById("chapter-bar");
			return bar ? JSON.parse(bar.dataset.chapters) : [];
		});
		bookId = page.url().match(/\/books\/(\d+)\/read/)?.[1];
		assert.ok(bookId, "openReader must land on a /books/:id/read/:cid URL");
		assert.ok(chapters.length >= 3, "fixture must seed ≥3 chapters");

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
				const next = await page.$eval("#audio-player", (el) => ({
					nextAudioUrl: el.dataset.nextAudioUrl || "",
					nextChapterId: el.dataset.nextChapterId || "",
				}));
				if (next.nextAudioUrl) {
					ch1 = String(ch.id);
					ch2 = next.nextChapterId;
					break;
				}
			}
		}
		assert.ok(
			ch1 && ch2,
			"fixture must seed ≥2 contiguous audio-ready chapters; check " +
				"`audio_for` in ReadaloudAudiobook.Fixtures.E2E.seed!/1.",
		);

		// The second boundary needs a THIRD consecutive audio-ready chapter.
		// Read it from the /nav endpoint — which is also the data source the
		// hook's prefetch bundle uses, so this doubles as an endpoint check.
		const nav = await page.evaluate(async (url) => {
			const r = await fetch(url);
			return r.ok ? r.json() : null;
		}, `${BASE_URL}/api/books/${bookId}/chapters/${ch2}/nav`);
		assert.ok(
			nav?.next?.audio_url,
			`chapter ${ch2} must have an audio-ready next chapter; check ` +
				"`audio_for: [1, 2, 3]` in ReadaloudAudiobook.Fixtures.E2E.seed!/1.",
		);
		ch3 = String(nav.next.chapter_id);

		// Enable auto-next-chapter and reload so the hook's PersistedRecord
		// cache picks it up, then wait for the initial src.
		await page.goto(`${BASE_URL}/books/${bookId}/read/${ch1}?nav=internal`, {
			waitUntil: "domcontentloaded",
		});
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
		await page.waitForFunction(
			() => {
				const a = document.getElementById("audio-element");
				return a?.src?.includes("/api/books/");
			},
			{ timeout: 5000 },
		);
	});

	after(async () => {
		// Safety net: every chapter serves this same WAV — leaving it
		// hidden after a mid-test failure would break every later file.
		restoreAudioFile();
		await teardown(browser);
	});

	it("second `ended` offline advances to chapter 3 via the prefetched nav window (no self-swap)", async () => {
		// Arm the prefetch bundle while the network still works: cross the
		// 15% trigger fraction and wait for BOTH the audio blob and the
		// /nav neighbors to land. This is the on-line half of the contract
		// — everything after this line runs with the network dead.
		await page.evaluate(
			() =>
				new Promise((resolve) => {
					const a = document.getElementById("audio-element");
					if (!a) return resolve();
					if (a.readyState >= 1 && Number.isFinite(a.duration))
						return resolve();
					a.addEventListener("loadedmetadata", () => resolve(), {
						once: true,
					});
				}),
		);
		await page.evaluate(() => {
			const a = document.getElementById("audio-element");
			if (!a || !Number.isFinite(a.duration)) return;
			a.currentTime = a.duration * 0.2;
			a.dispatchEvent(new Event("timeupdate"));
		});
		await waitForLog("prefetch-done", 20000);
		await waitForLog("prefetch-nav-done", 20000);

		// Kill the LV socket with no reconnect, then take the network down
		// entirely — the commute dead-zone regime. (See the comment at
		// `fixtureFile` for why going offline is two operations.)
		await page.evaluate(() => {
			window.liveSocket.disconnect();
			window.liveSocket.connect = () => {};
		});
		await page.waitForFunction(() => !window.liveSocket.isConnected(), {
			timeout: 5000,
		});
		await page.setOfflineMode(true);
		await page.waitForFunction(() => navigator.onLine === false, {
			timeout: 5000,
		});
		hideAudioFile();

		// FIRST boundary: ended on ch1 → swap to ch2's prefetched blob,
		// URL pushState's to ch2, and the window advances to ch2's
		// neighbors from the prefetched /nav payload.
		await page.evaluate(() => {
			document
				.getElementById("audio-element")
				.dispatchEvent(new Event("ended"));
		});
		await page.waitForFunction(
			(target) => {
				const a = document.getElementById("audio-element");
				const onUrl = window.location.pathname.match(/\/read\/(\d+)/)?.[1];
				return onUrl === target && a?.src?.startsWith("blob:");
			},
			{ timeout: 5000 },
			ch2,
		);
		assert.ok(
			sawLog("window-adopt"),
			"the swap must adopt ch2's neighbors from the prefetched /nav " +
				"payload — without it the second boundary has only the stale " +
				"dataset to navigate by",
		);

		// SECOND boundary: ended on ch2. The dataset still describes ch1
		// (the WS never delivered a refresh), so its "next" is ch2 — the
		// chapter that just finished. Pre-fix the hook swapped to it
		// (self-swap, restart at 0:00). Post-fix the window says ch3.
		await page.evaluate(() => {
			document
				.getElementById("audio-element")
				.dispatchEvent(new Event("ended"));
		});
		const advanced = await page
			.waitForFunction(
				(target) =>
					window.location.pathname.match(/\/read\/(\d+)/)?.[1] === target,
				{ timeout: 5000 },
				ch3,
			)
			.then(() => true)
			.catch(() => false);

		const state = await page.evaluate(() => {
			const a = document.getElementById("audio-element");
			return { url: window.location.pathname, audioSrc: a?.src ?? null };
		});

		assert.ok(
			!sawLog("nav-blocked-self-swap"),
			"with a prefetched nav window the second boundary must navigate " +
				"forward, not merely block a self-swap — blocking means the " +
				"window was empty/stale",
		);
		assert.ok(
			advanced,
			"URL did not advance to chapter 3 at the second offline boundary.\n" +
				`  url:       ${state.url}\n` +
				`  audio.src: ${state.audioSrc}\n` +
				`  expected:  /read/${ch3}\n\n` +
				"This is the second-boundary half of the 2026-06-11 incident: " +
				"the dataset still describes the pre-disconnect chapter, so " +
				"navigating by it re-targets the chapter that just finished. " +
				"The nav window prefetched alongside the audio blob must own " +
				"this decision.",
		);
		// Past the prefetch horizon there's no blob for ch3 (its prefetch
		// fails offline), so the swap targets the network URL — which can't
		// load yet. That's the expected degraded state the recovery test
		// below picks up from.
		assert.ok(
			state.audioSrc?.includes(`/chapters/${ch3}/audio`),
			`audio.src must target chapter 3's network URL, got ${state.audioSrc}`,
		);
	});

	it("retries the failed autoplay swap when connectivity returns", async () => {
		// Picks up from the previous test: audio.src points at ch3's network
		// URL, the load failed offline, and pendingAutoplay carries the
		// intent. Nothing else is scheduled to touch the element — only the
		// level-triggered retry can revive playback.
		// NOTE: `paused` is NOT a usable signal here — play() flips it
		// false synchronously and a failed load never flips it back. The
		// dead-element signature is "nothing ever loaded": readyState 0
		// (and usually a MediaError).
		const before = await page.evaluate(() => {
			const a = document.getElementById("audio-element");
			return {
				readyState: a.readyState,
				networkState: a.networkState,
				errorCode: a.error ? a.error.code : null,
				currentSrc: a.currentSrc,
			};
		});
		assert.strictEqual(
			before.readyState,
			0,
			"sanity: the offline swap must have left the element with nothing " +
				`loaded; got ${JSON.stringify(before)}\n` +
				"player log tail:\n  " +
				consoleLines
					.filter((l) => l.includes("[autoplay"))
					.slice(-25)
					.join("\n  "),
		);

		// Restore the audio file BEFORE reconnecting, so the retry the
		// `online` event triggers can actually fetch it.
		restoreAudioFile();
		await page.setOfflineMode(false);
		await page.waitForFunction(() => navigator.onLine === true, {
			timeout: 5000,
		});

		// The window `online` event fires the retry, which re-swaps from
		// the network URL and re-issues the load.
		await waitForLog("autoplay-retry", 10000);

		// Metadata arriving proves the audio was actually re-fetched over
		// the recovered network. (Whether play() then succeeds depends on
		// the browser's autoplay gesture policy — headless chromium may
		// block it — so playback itself is not asserted here; production
		// retains the OS media-session gesture from continuous playback.)
		await page.waitForFunction(
			(target) => {
				const a = document.getElementById("audio-element");
				return (
					a?.src?.includes(`/chapters/${target}/audio`) && a.readyState >= 1
				);
			},
			{ timeout: 10000 },
			ch3,
		);
	});
});
