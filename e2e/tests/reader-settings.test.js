import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader, openSettings, sleep } from "../helpers.js";

describe("Reader Settings", () => {
  let browser, page;

  before(async () => {
    ({ browser, page } = await setup());
    await openReader(page);
  });

  after(async () => {
    await teardown(browser);
  });

  describe("Auto Next Chapter Toggle", () => {
    it("toggle is visible in settings popover", async () => {
      await openSettings(page);
      const toggle = await page.$("#auto-next-chapter-toggle");
      assert.ok(toggle, "Auto next chapter toggle should exist");
    });

    it("toggle defaults to unchecked", async () => {
      const checked = await page.$eval(
        "#auto-next-chapter-toggle",
        (el) => el.checked
      );
      assert.strictEqual(checked, false, "Should default to unchecked");
    });

    it("toggling on persists to localStorage", async () => {
      await page.click("#auto-next-chapter-toggle");

      const stored = await page.evaluate(() => {
        const settings = JSON.parse(
          localStorage.getItem("readaloud-reader-settings") || "{}"
        );
        return settings.autoNextChapter;
      });
      assert.strictEqual(stored, true, "Should persist autoNextChapter=true");
    });

    it("toggle state survives page reload", async () => {
      // Reload the reader page
      await openReader(page);
      await openSettings(page);

      const checked = await page.$eval(
        "#auto-next-chapter-toggle",
        (el) => el.checked
      );
      assert.strictEqual(checked, true, "Toggle should remain checked after reload");

      // Clean up: uncheck
      await page.click("#auto-next-chapter-toggle");
    });
  });

  describe("Theme Selector", () => {
    it("theme swatches are visible in settings", async () => {
      await openSettings(page);
      const swatches = await page.$$("[data-set-theme]");
      assert.ok(swatches.length > 10, `Should have many theme swatches, got ${swatches.length}`);
    });

    it("dark and light groups both exist", async () => {
      const darkLabel = await page.$eval(
        "#reader-settings",
        (el) => el.textContent.includes("Dark")
      );
      const lightLabel = await page.$eval(
        "#reader-settings",
        (el) => el.textContent.includes("Light")
      );
      assert.ok(darkLabel, "Should have Dark themes group");
      assert.ok(lightLabel, "Should have Light themes group");
    });

    it("clicking a swatch changes the theme", async () => {
      const themeBefore = await page.evaluate(() =>
        document.documentElement.getAttribute("data-theme")
      );

      // Click the 'dracula' theme swatch
      await page.click('[data-set-theme="dracula"]');
      await sleep(200);

      const themeAfter = await page.evaluate(() =>
        document.documentElement.getAttribute("data-theme")
      );
      assert.strictEqual(themeAfter, "dracula", "Theme should change to dracula");

      // Verify localStorage
      const stored = await page.evaluate(() =>
        localStorage.getItem("phx:theme")
      );
      assert.strictEqual(stored, "dracula");
    });

    it("active swatch gets highlighted", async () => {
      const hasActive = await page.$eval(
        '[data-set-theme="dracula"]',
        (el) => el.classList.contains("active")
      );
      assert.ok(hasActive, "Active swatch should have 'active' class");

      // Other swatches should not be active
      const otherActive = await page.$eval(
        '[data-set-theme="dark"]',
        (el) => el.classList.contains("active")
      );
      assert.strictEqual(otherActive, false, "Non-active swatch should not have 'active' class");
    });

    it("theme persists after reload", async () => {
      await openReader(page);
      const theme = await page.evaluate(() =>
        document.documentElement.getAttribute("data-theme")
      );
      assert.strictEqual(theme, "dracula", "Theme should persist after reload");

      // Restore default
      await page.evaluate(() => {
        document.documentElement.setAttribute("data-theme", "dark");
        localStorage.setItem("phx:theme", "dark");
      });
    });
  });

  describe("Settings Popover Scrollability", () => {
    it("settings popover has overflow-y-auto for small screens", async () => {
      await openSettings(page);
      const hasOverflow = await page.$eval("#reader-settings", (el) => {
        const style = getComputedStyle(el);
        return style.overflowY === "auto";
      });
      assert.ok(hasOverflow, "Settings popover should have overflow-y: auto");
    });
  });
});
