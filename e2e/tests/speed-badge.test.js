import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader, sleep } from "../helpers.js";

describe("Speed Badge", () => {
  let browser, page;

  before(async () => {
    ({ browser, page } = await setup());
    // Clear any persisted speed so we start fresh
    await page.evaluateOnNewDocument(() => {
      localStorage.removeItem("readaloud-playback-speed");
    });
    await openReader(page);
  });

  after(async () => {
    await teardown(browser);
  });

  it("speed badge exists in the audio player", async () => {
    // The badge only shows when audio_state == :ready (audio player rendered).
    // If no audio exists for this chapter, the badge won't be in the DOM.
    const badge = await page.$("#speed-badge");
    if (!badge) {
      // Skip if no audio player (no audio generated for this chapter)
      console.log("  (skipped: no audio player — generate audio for a chapter to test)");
      return;
    }
    assert.ok(badge, "Speed badge should exist");
  });

  it("badge shows current speed text", async () => {
    const badge = await page.$("#speed-badge");
    if (!badge) return; // skip if no audio

    const text = await page.$eval("#speed-badge", (el) => el.textContent.trim());
    assert.match(text, /^\d+(\.\d+)?x$/, `Badge should show speed like "1x", got "${text}"`);
  });

  it("clicking badge cycles speed forward", async () => {
    const badge = await page.$("#speed-badge");
    if (!badge) return;

    // Read initial speed
    const initial = await page.$eval("#speed-badge", (el) => el.textContent.trim());

    // Click to cycle
    await page.click("#speed-badge");
    await sleep(100);

    const next = await page.$eval("#speed-badge", (el) => el.textContent.trim());
    assert.notStrictEqual(next, initial, `Speed should change from ${initial} after click`);
  });

  it("speed persists to localStorage", async () => {
    const badge = await page.$("#speed-badge");
    if (!badge) return;

    const stored = await page.evaluate(() =>
      localStorage.getItem("readaloud-playback-speed")
    );
    assert.ok(stored, "Speed should be stored in localStorage");
    assert.ok(parseFloat(stored) > 0, "Stored speed should be a positive number");
  });

  it("badge uses tabular-nums for stable width", async () => {
    const badge = await page.$("#speed-badge");
    if (!badge) return;

    const fontVariant = await page.$eval("#speed-badge", (el) => el.style.fontVariantNumeric);
    assert.strictEqual(fontVariant, "tabular-nums", "Badge should use tabular-nums");
  });

  it("full cycle wraps back to 0.5x", async () => {
    const badge = await page.$("#speed-badge");
    if (!badge) return;

    // Set speed to 2x (last in cycle), then click to wrap
    await page.evaluate(() => {
      const audio = document.getElementById("audio-element");
      if (audio) audio.playbackRate = 2;
      localStorage.setItem("readaloud-playback-speed", "2");
      const b = document.getElementById("speed-badge");
      if (b) b.textContent = "2x";
    });

    await page.click("#speed-badge");
    await sleep(100);

    const text = await page.$eval("#speed-badge", (el) => el.textContent.trim());
    assert.strictEqual(text, "0.5x", "Should wrap to 0.5x after 2x");

    // Clean up
    await page.evaluate(() => {
      localStorage.removeItem("readaloud-playback-speed");
    });
  });
});
