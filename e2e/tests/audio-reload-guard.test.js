/**
 * Reload-guard regression: LiveView's hard-reload recovery must not kill
 * background audio playback.
 *
 * Reproduces the 2026-06-10 production incident (book 12, ch 820→821,
 * reconstructed from the [player] diagnostics channel):
 *
 *   - Phone screen locked, audio playing. The OS silently suspends the
 *     tab's network: the LV WebSocket is dead but the client doesn't
 *     know it yet (no FIN arrives — a "zombie" socket).
 *   - Chapter ends. The hook's client-owned advance works perfectly:
 *     swap to the prefetched blob, audio.play() OK, pushState URL.
 *   - The hook also calls pushEvent("next_chapter"). The channel still
 *     believes it's connected, so the push goes into the void and times
 *     out after PUSH_TIMEOUT (30s).
 *   - phoenix_live_view's recovery for a push timeout (view.js
 *     pushWithReply) is liveSocket.reloadWithJitter → 5-10s jitter →
 *     window.location.reload(). Join errors and close-1000 failsafe
 *     converge on the same path.
 *   - The reload destroys the playing blob audio mid-chapter, loses the
 *     autoplay gesture, and the fresh page mounts paused at 0:00. The
 *     suspended tab then aborts its own audio preloads and goes dark —
 *     the user wakes the phone to silence and "could not connect".
 *
 * Invariant this test pins: while the page is hidden and the reader
 * audio is actively playing, reloadWithJitter must NOT reload the page.
 * Once the page is visible again with a healthy socket, no reload
 * happens either (recovery is rejoin, not reload).
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader } from "../helpers.js";

// Stock reloadWithJitter fires after reloadJitterMin..Max (5-10s by
// default). Those are mutable LiveSocket instance fields read at call
// time, so the test shrinks the window — a broken guard still reloads,
// just within milliseconds instead of seconds, and the negative
// assertion only has to outwait the shrunk window plus page-load time.
const JITTER_MIN_MS = 50;
const JITTER_MAX_MS = 250;
const SLACK_MS = 1_750;

describe("Background-audio reload guard", () => {
	let browser, page;

	before(async () => {
		({ browser, page } = await setup());
		await openReader(page);
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

	it("defers LV's hard-reload recovery while hidden audio is playing", async () => {
		// Start playback. Muted so headless Chrome's autoplay policy
		// allows it without a gesture — the guard only cares about
		// `!audio.paused`.
		await page.evaluate(async () => {
			const a = document.getElementById("audio-element");
			a.muted = true;
			await a.play();
		});

		// Emulate the locked screen: visibilityState becomes "hidden".
		// Plant a marker that a page reload would wipe, and shrink the
		// jitter window so a regression reloads fast instead of in 5-10s.
		await page.evaluate(
			([min, max]) => {
				window.liveSocket.reloadJitterMin = min;
				window.liveSocket.reloadJitterMax = max;
				window.__reloadGuardMarker = true;
			},
			[JITTER_MIN_MS, JITTER_MAX_MS],
		);
		await page.evaluate(() => {
			Object.defineProperty(document, "visibilityState", {
				value: "hidden",
				configurable: true,
			});
			Object.defineProperty(document, "hidden", {
				value: true,
				configurable: true,
			});
			document.dispatchEvent(new Event("visibilitychange"));
		});

		// Trigger the recovery path all three production triggers (push
		// timeout, join error, close-1000 failsafe) converge on.
		await page.evaluate(() => {
			window.liveSocket.reloadWithJitter(window.liveSocket.main);
		});

		// Stock behavior: view.destroy() + window.location.reload() within
		// the (shrunk) jitter window. Wait past it plus page-load slack to
		// prove the reload did not happen.
		await new Promise((r) => setTimeout(r, JITTER_MAX_MS + SLACK_MS));

		const afterHidden = await page.evaluate(() => ({
			marker: window.__reloadGuardMarker === true,
			audioPlaying: (() => {
				const a = document.getElementById("audio-element");
				return !!a && !a.paused;
			})(),
		}));

		assert.ok(
			afterHidden.marker,
			"Page reloaded while hidden audio was playing — LV's " +
				"reloadWithJitter recovery killed the background listening " +
				"session (the 2026-06-10 incident). The reload must be " +
				"deferred until the page is visible again.",
		);
		assert.ok(
			afterHidden.audioPlaying,
			"Audio element stopped playing during the hidden window.",
		);

		// Screen comes back on. The socket here is healthy (we never
		// actually broke it), so the deferred reload must be skipped —
		// recovery is rejoin, not reload. The guard announces that exact
		// outcome with readaloud:lv-reload-resumed once the reconnect
		// grace elapses — wait on the event instead of sleeping past it.
		await page.evaluate(() => {
			window.__reloadResumedSeen = false;
			window.addEventListener(
				"readaloud:lv-reload-resumed",
				() => {
					window.__reloadResumedSeen = true;
				},
				{ once: true },
			);
			Object.defineProperty(document, "visibilityState", {
				value: "visible",
				configurable: true,
			});
			Object.defineProperty(document, "hidden", {
				value: false,
				configurable: true,
			});
			document.dispatchEvent(new Event("visibilitychange"));
		});

		// Fires after RELOAD_RECONNECT_GRACE_MS (4s); generous timeout.
		await page.waitForFunction(() => window.__reloadResumedSeen === true, {
			timeout: 10_000,
		});

		const afterVisible = await page.evaluate(() => ({
			marker: window.__reloadGuardMarker === true,
			socketConnected: window.liveSocket.isConnected(),
		}));

		assert.ok(
			afterVisible.socketConnected,
			"sanity: socket should still be connected in this scenario",
		);
		assert.ok(
			afterVisible.marker,
			"Page reloaded after becoming visible even though the socket " +
				"was connected — the deferred reload must be skipped when " +
				"the socket has recovered.",
		);
	});
});
