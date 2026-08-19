/**
 * Autoplay chain across THREE offline chapter boundaries + recovery past
 * the prefetch horizon.
 *
 * audio-autoplay-disconnect.test.js pins the FIRST boundary: with the LV
 * socket dead, `ended` still swaps audio.src and pushState's the URL.
 * This file pins two commute incidents on top of that:
 *
 * 2026-06-11 — the SECOND boundary:
 *   - Chapter N ends offline; the hook swaps to N+1's prefetched blob.
 *     The server never delivers a dataset refresh (WS is dead), so the
 *     dataset still describes chapter N — whose "next" is N+1.
 *   - Chapter N+1 ends. Pre-fix, the hook read its nav target from the
 *     stale dataset and "advanced" to N+1 — the chapter that just
 *     finished — restarting it at 0:00 over a network URL with no
 *     network (NETWORK_NO_SOURCE) and clobbering the position cache.
 *   Fix: the prefetch bundle also fetches /nav, so a cached chapter's
 *   own neighbors are client-local (CHAPTER_WINDOW) by the time it plays;
 *   a self-swap guard refuses targets equal to the loaded chapter.
 *
 * 2026-08-18 — the prefetch HORIZON:
 *   - Android cut the page's network for ~6 minutes with the screen off
 *     (fetch() threw, navigator.onLine stayed true). The single-slot
 *     prefetch was triggered at 15% of the chapter and reached ONE
 *     chapter ahead, so the blackout spanned the whole prefetch window:
 *     the next boundary had no blob, the swap targeted a network URL,
 *     silence until the user woke the phone.
 *   Fix: a cache of the next PREFETCH_HORIZON (3) chapters — audio blob
 *   + /nav each — filled from the moment playback starts (first
 *   `timeupdate` / `play`), refilled on every swap, and retried on
 *   online / visible. The chain consumes it with no server round-trip.
 *
 * Requires the canonical fixture's five consecutive audio-ready chapters
 * (`audio_for: [1, 2, 3, 4, 5]`): from chapter 1 the horizon covers 2–4,
 * chapter 5 is past it, and the swap into 5 is the degraded state the
 * recovery test picks up from.
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { existsSync, renameSync } from "node:fs";
import { setup, teardown, openReader, BASE_URL } from "../helpers.js";

describe("Autoplay across three offline chapter boundaries", () => {
	let browser, page;
	/** Every console line the page emits; the hook's log() mirrors all
	 * player events to console.log("[autoplay <ts>] <event>", {...}). */
	const consoleLines = [];
	/** The same events, parsed: {event, detail}. `detail` is the log's
	 * extra-fields object, resolved asynchronously from the console arg
	 * (null until then) — waiters that need it poll until it lands. */
	const consoleEvents = [];
	const sawLog = (event) =>
		consoleLines.some((line) => line.includes(`] ${event}`));
	const sawEvent = (event, pred) =>
		consoleEvents.some(
			(rec) =>
				rec.event === event &&
				(pred === undefined || (rec.detail !== null && pred(rec.detail))),
		);
	const waitForEvent = async (event, pred, timeoutMs = 5000, what = "") => {
		const deadline = Date.now() + timeoutMs;
		while (Date.now() < deadline) {
			if (sawEvent(event, pred)) return;
			await new Promise((r) => setTimeout(r, 100));
		}
		throw new Error(
			`expected console log event "${event}"${what ? ` (${what})` : ""} ` +
				`within ${timeoutMs}ms; player log tail:\n  ` +
				consoleLines
					.filter((l) => l.includes("[autoplay"))
					.slice(-30)
					.join("\n  "),
		);
	};
	const waitForLog = (event, timeoutMs) =>
		waitForEvent(event, undefined, timeoutMs);
	const forChapter = (chapterId) => (d) =>
		typeof d.url === "string" && d.url.includes(`/chapters/${chapterId}/`);

	let bookId;
	let ch1, ch2, ch3, ch4, ch5; // chapter ids (strings), all audio-ready

	// Making a media load FAIL while "offline" needs two mechanisms:
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
		page.on("console", (msg) => {
			const text = msg.text();
			consoleLines.push(text);
			const m = text.match(/^\[autoplay [^\]]+\] (\S+)/);
			if (!m) return;
			const rec = { event: m[1], detail: null };
			consoleEvents.push(rec);
			const arg = msg.args()[1];
			if (arg) {
				arg
					.jsonValue()
					.then((v) => {
						rec.detail = v && typeof v === "object" ? v : {};
					})
					.catch(() => {
						rec.detail = {};
					});
			} else {
				rec.detail = {};
			}
		});

		// Walk to a chapter with audio AND a next-audio chapter (same
		// precondition walk as audio-autoplay.test.js).
		await openReader(page);
		const chapters = await page.evaluate(() => {
			const bar = document.getElementById("chapter-bar");
			return bar ? JSON.parse(bar.dataset.chapters) : [];
		});
		bookId = page.url().match(/\/books\/(\d+)\/read/)?.[1];
		assert.ok(bookId, "openReader must land on a /books/:id/read/:cid URL");
		assert.ok(chapters.length >= 5, "fixture must seed ≥5 chapters");

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
					break;
				}
			}
		}
		assert.ok(
			ch1,
			"fixture must seed ≥2 contiguous audio-ready chapters; check " +
				"`audio_for` in ReadaloudAudiobook.Fixtures.E2E.seed!/1.",
		);

		// Three boundaries inside the horizon plus one past it need FIVE
		// consecutive audio-ready chapters. Follow the /nav endpoint —
		// which is also the data source the hook's prefetch walk uses, so
		// this doubles as an endpoint check.
		const chain = [ch1];
		for (let i = 0; i < 4; i++) {
			const cur = chain[chain.length - 1];
			const nav = await page.evaluate(async (url) => {
				const r = await fetch(url);
				return r.ok ? r.json() : null;
			}, `${BASE_URL}/api/books/${bookId}/chapters/${cur}/nav`);
			assert.ok(
				nav?.next?.audio_url,
				`chapter ${cur} must have an audio-ready next chapter; check ` +
					"`audio_for: [1, 2, 3, 4, 5]` in " +
					"ReadaloudAudiobook.Fixtures.E2E.seed!/1.",
			);
			chain.push(String(nav.next.chapter_id));
		}
		[ch1, ch2, ch3, ch4, ch5] = chain;

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

	it("fills a 3-chapter horizon on the first timeupdate and chains three offline boundaries from it", async () => {
		// Arm the prefetch cache while the network still works: the first
		// timeupdate is playback evidence, and the fill walks the window →
		// /nav → /nav out to PREFETCH_HORIZON. Wait for all three blobs.
		// This is the on-line half of the contract — everything after the
		// horizon lands runs with the network dead.
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
			// Well under the old 15% trigger: the fill must not wait for
			// playback progress — the network may be gone by then.
			a.currentTime = a.duration * 0.02;
			a.dispatchEvent(new Event("timeupdate"));
		});
		await waitForEvent("prefetch-done", forChapter(ch2), 20000, `ch ${ch2}`);
		await waitForEvent("prefetch-done", forChapter(ch3), 20000, `ch ${ch3}`);
		await waitForEvent("prefetch-done", forChapter(ch4), 20000, `ch ${ch4}`);
		await waitForEvent(
			"prefetch-horizon",
			(d) => d.depth === 3,
			10000,
			"depth 3",
		);
		assert.ok(
			sawEvent("prefetch-nav-done", forChapter(ch4)),
			"the depth-3 entry must carry its own /nav neighbors too — that " +
				"is what lets the chain keep walking after the network dies",
		);
		assert.ok(
			!sawEvent("prefetch-start", forChapter(ch5)),
			`chapter ${ch5} is past the 3-chapter horizon from ${ch1}; it must ` +
				"not be fetched yet (memory is bounded by the horizon)",
		);

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

		const dispatchEnded = () =>
			page.evaluate(() => {
				document
					.getElementById("audio-element")
					.dispatchEvent(new Event("ended"));
			});
		const waitForBlobSwapTo = (target) =>
			page.waitForFunction(
				(t) => {
					const a = document.getElementById("audio-element");
					const onUrl = window.location.pathname.match(/\/read\/(\d+)/)?.[1];
					return onUrl === t && a?.src?.startsWith("blob:");
				},
				{ timeout: 5000 },
				target,
			);
		const currentState = () =>
			page.evaluate(() => {
				const a = document.getElementById("audio-element");
				return { url: window.location.pathname, audioSrc: a?.src ?? null };
			});
		const blobSwapFailure = async (target, boundary) => {
			const state = await currentState();
			return (
				`boundary ${boundary}: did not swap to chapter ${target}'s cached ` +
				"blob offline.\n" +
				`  url:       ${state.url}\n` +
				`  audio.src: ${state.audioSrc}\n` +
				`  expected:  /read/${target} + blob: src\n\n` +
				"player log tail:\n  " +
				consoleLines
					.filter((l) => l.includes("[autoplay"))
					.slice(-30)
					.join("\n  ")
			);
		};

		// FIRST boundary: ended on ch1 → swap to ch2's cached blob, URL
		// pushState's to ch2, and the window advances to ch2's neighbors
		// from the cached /nav payload.
		await dispatchEnded();
		await waitForBlobSwapTo(ch2).catch(async () => {
			assert.fail(await blobSwapFailure(ch2, 1));
		});
		assert.ok(
			sawLog("window-adopt"),
			"the swap must adopt ch2's neighbors from the cached /nav " +
				"payload — without it the next boundary has only the stale " +
				"dataset to navigate by",
		);
		// The swap re-aims the cache at the new window (ch3, ch4, ch5): ch5
		// is fetched now, offline, and fails. That failure must be logged
		// with the connectivity snapshot — and must not stop the chain.
		await waitForEvent(
			"prefetch-fail",
			forChapter(ch5),
			10000,
			`ch ${ch5}, offline`,
		);
		assert.ok(
			sawEvent(
				"prefetch-fail",
				(d) => forChapter(ch5)(d) && d.online === false,
			),
			"prefetch-fail must carry navigator.onLine so a blackout can be " +
				"told apart from a Doze-class restriction in the incident log",
		);

		// SECOND boundary: ended on ch2. The dataset still describes ch1
		// (the WS never delivered a refresh), so its "next" is ch2 — the
		// chapter that just finished. Pre-2026-06-11-fix the hook swapped
		// to it (self-swap, restart at 0:00). The window says ch3, and the
		// horizon has ch3's blob.
		await dispatchEnded();
		await waitForBlobSwapTo(ch3).catch(async () => {
			assert.fail(await blobSwapFailure(ch3, 2));
		});

		// THIRD boundary: ended on ch3 → ch4, still from the blob cache
		// filled back on ch1. This is the boundary the 2026-08-18 blackout
		// starved: with a 1-chapter horizon there was nothing here.
		await dispatchEnded();
		await waitForBlobSwapTo(ch4).catch(async () => {
			assert.fail(await blobSwapFailure(ch4, 3));
		});

		assert.ok(
			!sawLog("nav-blocked-self-swap"),
			"with cached nav windows every boundary must navigate forward, " +
				"not merely block a self-swap — blocking means a window was " +
				"empty/stale",
		);
		assert.ok(
			!sawLog("next-chapter-blocked-no-target"),
			"no boundary inside the horizon may run out of nav targets",
		);
		assert.ok(
			!sawLog("sync-audio-to-dataset"),
			"the reconciler must not fire — the dataset is frozen on ch1 and " +
				"the socket is dead; every move here is client-owned",
		);

		// FOURTH boundary: ended on ch4 → ch5 is PAST the horizon we filled
		// on ch1, and its fetch failed offline, so the swap targets the
		// network URL — which can't load yet. That's the expected degraded
		// state the recovery test below picks up from.
		await dispatchEnded();
		await page.waitForFunction(
			(target) =>
				window.location.pathname.match(/\/read\/(\d+)/)?.[1] === target,
			{ timeout: 5000 },
			ch5,
		);
		const state = await currentState();
		assert.ok(
			state.audioSrc?.includes(`/chapters/${ch5}/audio`),
			`audio.src must target chapter 5's network URL past the horizon, ` +
				`got ${state.audioSrc}`,
		);
	});

	it("retries the failed autoplay swap when connectivity returns", async () => {
		// Picks up from the previous test: audio.src points at ch5's network
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
			ch5,
		);
	});
});
