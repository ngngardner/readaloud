/**
 * Autoplay regression: LV socket rejoin after a client-owned chapter nav.
 *
 * Reproduces the 2026-08-18 commute incident (book 22, ch 16806→16812):
 * three times, the moment the phone screen came back on, audio snapped
 * BACKWARDS to a chapter finished 5–10 minutes earlier. Every time the
 * screen goes off Android kills the LV WebSocket; on wake it rejoins.
 * The rejoin's `url` param is LiveView's own `View.href` — set at page
 * load, on a *delivered* server push_patch, or an LV link click. Our
 * client-owned autoplay nav updates the URL with raw `history.pushState`
 * (which never touches `View.href`), and the server deliberately skips
 * push_patch for client-owned navs. So `View.href` sits at the page-load
 * chapter for the whole session, the rejoin re-mounts THAT chapter, the
 * hook's dataset transitions backwards, and `syncAudioToDataset` — whose
 * contract is "a dataset transition means the server moved the chapter"
 * — obediently swaps the audio back.
 *
 * Minimal reproduction (no offline needed): one online client-owned nav
 * (server reconciles, dataset advances to N+1) followed by a socket
 * disconnect/reconnect — exactly what `readaloud:force-reconnect` does
 * and what Phoenix's own reconnect does after a dead-socket wake.
 *
 * Invariant this test pins: after a client-owned nav, a socket rejoin
 * must land the LV on the chapter that's actually playing. The dataset,
 * URL and audio.src must all still say N+1, and the reconciler must not
 * fire a backwards `sync-audio-to-dataset`.
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader, BASE_URL } from "../helpers.js";

describe("Autoplay across LV socket rejoin", () => {
	let browser, page;

	/** Every console line the page emits; the hook's log() mirrors all
	 * player events to console.log("[autoplay <ts>] <event>", {...}). */
	const consoleLines = [];
	const sawLog = (event) =>
		consoleLines.some((line) => line.includes(`] ${event}`));

	let ch1, ch2; // chapter ids (strings), both audio-ready

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
		const bookId = page.url().match(/\/books\/(\d+)\/read/)?.[1];
		assert.ok(bookId, "openReader must land on a /books/:id/read/:cid URL");
		assert.ok(chapters.length > 0, "fixture must seed ≥1 chapter");

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

		// Enable autoplay and reload so the hook's PersistedRecord cache
		// picks up the new value on its next mount. After this reload the
		// page-load URL — and therefore LiveView's View.href — is ch1.
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
		await page.waitForSelector("[data-phx-session].phx-connected", {
			timeout: 10000,
		});
		await page.waitForSelector("#audio-element", { timeout: 10000 });
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

	const snapshot = () =>
		page.evaluate(() => {
			const a = document.getElementById("audio-element");
			const player = document.getElementById("audio-player");
			return {
				url: window.location.pathname,
				datasetChapterId: player?.dataset.chapterId ?? null,
				audioSrc: a?.src ?? null,
				socketConnected: window.liveSocket.isConnected(),
			};
		});

	it("rejoin after a client-owned nav mounts the playing chapter, not the page-load chapter", async () => {
		const before = await snapshot();
		assert.strictEqual(before.datasetChapterId, ch1, "sanity: on ch1");

		// --- Step 1: ONLINE client-owned autoplay nav ch1 → ch2. --------
		// The hook swaps audio.src, pushState's the URL, buffers a pivot
		// observation and pushes `next_chapter{client_owned: true}`. The
		// server reconciles assigns to ch2 (dataset follows) but — client
		// owned — skips push_patch, so View.href stays at ch1.
		await page.evaluate(() => {
			document
				.getElementById("audio-element")
				.dispatchEvent(new Event("ended"));
		});
		await page.waitForFunction(
			(target) =>
				window.location.pathname.match(/\/read\/(\d+)/)?.[1] === target,
			{ timeout: 5000 },
			ch2,
		);
		await page.waitForFunction(
			(target) =>
				document.getElementById("audio-player")?.dataset.chapterId === target,
			{ timeout: 5000 },
			ch2,
		);
		const afterNav = await snapshot();
		assert.ok(
			!afterNav.audioSrc?.includes(`/chapters/${ch1}/audio`),
			`sanity: audio must have left ch1, got ${afterNav.audioSrc}`,
		);
		assert.strictEqual(afterNav.socketConnected, true, "sanity: online");

		// --- Step 2: socket dies and rejoins (screen off → screen on). --
		// Split into explicit disconnect → wait → connect so the rejoin is
		// observable; `readaloud:force-reconnect` does the same two calls
		// back to back.
		await page.evaluate(() => window.liveSocket.disconnect());
		await page.waitForFunction(
			() =>
				!window.liveSocket.isConnected() &&
				!document
					.querySelector("[data-phx-session]")
					?.classList.contains("phx-connected"),
			{ timeout: 5000 },
		);
		await page.evaluate(() => window.liveSocket.connect());
		await page.waitForSelector("[data-phx-session].phx-connected", {
			timeout: 10000,
		});

		// Give a stale-URL remount time to land its diff. Pre-fix the
		// dataset flips back to ch1 within a few hundred ms of the join;
		// waiting for the *bug* (bounded) keeps the pass path fast-ish
		// while never letting a slow diff sneak past the assertions.
		await page
			.waitForFunction(
				(target) =>
					document.getElementById("audio-player")?.dataset.chapterId !== target,
				{ timeout: 3000 },
				ch2,
			)
			.catch(() => {});

		const after = await snapshot();
		assert.strictEqual(after.socketConnected, true, "sanity: rejoined");

		const explain =
			`  page-load chapter: ${ch1}\n` +
			`  playing chapter:   ${ch2}\n` +
			`  url:               ${after.url}\n` +
			`  dataset chapter:   ${after.datasetChapterId}\n` +
			`  audio.src:         ${after.audioSrc}\n\n` +
			"This is the 2026-08-18 commute pull-back: LiveView rejoins with " +
			"its own View.href (still the page-load URL — raw history.pushState " +
			"never updates it and client-owned navs skip push_patch), the " +
			"server re-mounts the page-load chapter, the dataset transitions " +
			"backwards and syncAudioToDataset swaps the audio back to a " +
			"chapter that already finished.";

		assert.strictEqual(
			after.datasetChapterId,
			ch2,
			`LV rejoin re-mounted the page-load chapter instead of the one playing.\n${explain}`,
		);
		assert.ok(
			!after.audioSrc?.includes(`/chapters/${ch1}/audio`),
			`audio.src was pulled back to the page-load chapter after rejoin.\n${explain}`,
		);
		assert.ok(
			after.url.endsWith(`/read/${ch2}`),
			`URL regressed after rejoin.\n${explain}`,
		);
		assert.ok(
			!sawLog("sync-audio-to-dataset"),
			"the reconciler fired sync-audio-to-dataset on rejoin — a " +
				"rehydration was treated as a server-owned chapter move.\n" +
				explain +
				"\n\nlast console lines:\n  " +
				consoleLines.slice(-25).join("\n  "),
		);
	});

	it("re-asserts the playing chapter when a rejoin re-mounts a stale one", async () => {
		// Defense in depth for any OTHER way View.href (or whatever the
		// server mounts from) can lag the audio. Picks up from the previous
		// test: connected, on ch2. Force LiveView's href back to ch1 — the
		// exact pre-fix state — then rejoin. The server re-mounts ch1 and
		// the hook's dataset transitions backwards; the hook must treat
		// that as a rehydration (re-assert ch2 with a pivot so the server's
		// reconciler converges) rather than a server-owned move to follow.
		const start = await snapshot();
		assert.strictEqual(start.datasetChapterId, ch2, "precondition: on ch2");
		assert.strictEqual(start.socketConnected, true, "precondition: online");

		const staleHref = await page.evaluate((chapterId) => {
			const href = `${window.location.origin}/books/${
				window.location.pathname.match(/\/books\/(\d+)\//)[1]
			}/read/${chapterId}?nav=internal`;
			window.liveSocket.main.setHref(href);
			return href;
		}, ch1);
		assert.ok(staleHref.includes(`/read/${ch1}`), "sanity: href forced to ch1");

		await page.evaluate(() => window.liveSocket.disconnect());
		await page.waitForFunction(
			() =>
				!window.liveSocket.isConnected() &&
				!document
					.querySelector("[data-phx-session]")
					?.classList.contains("phx-connected"),
			{ timeout: 5000 },
		);
		await page.evaluate(() => window.liveSocket.connect());
		await page.waitForSelector("[data-phx-session].phx-connected", {
			timeout: 10000,
		});

		// The stale mount lands ch1 in the dataset; the hook re-asserts ch2
		// and the server converges back. Wait for the round-trip.
		const converged = await page
			.waitForFunction(
				(target) =>
					document.getElementById("audio-player")?.dataset.chapterId === target,
				{ timeout: 10000 },
				ch2,
			)
			.then(() => true)
			.catch(() => false);
		// Let any straggling diff land before judging the audio element.
		await new Promise((r) => setTimeout(r, 500));

		const after = await snapshot();
		const explain =
			`  stale mount chapter: ${ch1}\n` +
			`  playing chapter:     ${ch2}\n` +
			`  url:                 ${after.url}\n` +
			`  dataset chapter:     ${after.datasetChapterId}\n` +
			`  audio.src:           ${after.audioSrc}\n\n` +
			"last console lines:\n  " +
			consoleLines.slice(-25).join("\n  ");

		assert.ok(
			sawLog("rejoin-reassert-chapter"),
			`hook did not re-assert the loaded chapter on the stale rejoin patch.\n${explain}`,
		);
		assert.ok(
			!after.audioSrc?.includes(`/chapters/${ch1}/audio`),
			`audio.src was pulled back to the stale-mounted chapter.\n${explain}`,
		);
		assert.ok(
			!sawLog("sync-audio-to-dataset"),
			`the rejoin patch was treated as a server-owned move.\n${explain}`,
		);
		assert.ok(
			converged,
			`server assigns never converged back onto the playing chapter.\n${explain}`,
		);
		assert.ok(after.url.endsWith(`/read/${ch2}`), `URL regressed.\n${explain}`);
	});
});
