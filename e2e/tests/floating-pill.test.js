import { describe, it, before, after } from "node:test";
import assert from "node:assert";
import { setup, teardown, openReader, showPill, sleep, getChapters } from "../helpers.js";

describe("Floating Pill", () => {
  let browser, page;

  before(async () => {
    ({ browser, page } = await setup());
    await openReader(page);
  });

  after(async () => {
    await teardown(browser);
  });

  describe("Pill Visibility", () => {
    it("pill starts hidden", async () => {
      const hasOpacity0 = await page.$eval("#floating-pill", (el) =>
        el.classList.contains("opacity-0")
      );
      assert.ok(hasOpacity0, "Pill should start with opacity-0");
    });

    it("pill appears on mouse movement", async () => {
      await showPill(page);
      const visible = await page.$eval("#floating-pill", (el) =>
        el.classList.contains("opacity-100")
      );
      assert.ok(visible, "Pill should become visible on mouse move");
    });
  });

  describe("Pill Buttons", () => {
    it("has home button linking to library", async () => {
      await showPill(page);
      const homeLink = await page.$eval(
        '#floating-pill a[title="Library"]',
        (el) => el.getAttribute("href")
      );
      assert.strictEqual(homeLink, "/", "Home button should link to /");
    });

    it("has home button with hero-home icon", async () => {
      const icon = await page.$(
        '#floating-pill a[title="Library"] [class*="hero-home"]'
      );
      assert.ok(icon, "Home button should use hero-home icon");
    });

    it("has chapter indicator showing current position", async () => {
      const indicator = await page.$("#chapter-indicator");
      assert.ok(indicator, "Chapter indicator should exist");

      const text = await page.$eval("#chapter-indicator", (el) =>
        el.textContent.trim()
      );
      assert.match(text, /Ch \d+ \/ \d+/, `Indicator should show "Ch X / Y", got "${text}"`);
    });

    it("has settings gear button", async () => {
      const gear = await page.$('#floating-pill button[phx-click]');
      assert.ok(gear, "Settings gear button should exist");
    });

    it("has prev/next chapter navigation", async () => {
      // At least one of prev/next should exist (unless single chapter book)
      const prevBtn = await page.$('#floating-pill [class*="hero-chevron-left"]');
      const nextBtn = await page.$('#floating-pill [class*="hero-chevron-right"]');
      assert.ok(prevBtn || nextBtn, "Should have at least one prev/next button");
    });

    it("prev button is disabled on first chapter", async () => {
      const chapters = await getChapters(page);
      const currentIdx = await page.$eval("#chapter-bar", (el) =>
        parseInt(el.dataset.currentIndex)
      );

      if (currentIdx === 0) {
        // On first chapter — prev should be disabled
        const disabled = await page.$('#floating-pill button[disabled] [class*="hero-chevron-left"]');
        assert.ok(disabled, "Prev button should be disabled on first chapter");
      }
    });

    it("next button is disabled on last chapter", async () => {
      const chapters = await getChapters(page);
      const currentIdx = await page.$eval("#chapter-bar", (el) =>
        parseInt(el.dataset.currentIndex)
      );

      if (currentIdx === chapters.length - 1) {
        const disabled = await page.$('#floating-pill button[disabled] [class*="hero-chevron-right"]');
        assert.ok(disabled, "Next button should be disabled on last chapter");
      }
    });

    it("prev/next links include ?nav=internal", async () => {
      const links = await page.$$eval('#floating-pill a[href*="/read/"]', (els) =>
        els.map((el) => el.getAttribute("href"))
      );
      for (const href of links) {
        assert.ok(
          href.includes("nav=internal"),
          `Nav link ${href} should include ?nav=internal`
        );
      }
    });
  });
});

describe("Chapter Bar", () => {
  let browser, page;

  before(async () => {
    ({ browser, page } = await setup());
    await openReader(page);
  });

  after(async () => {
    await teardown(browser);
  });

  describe("Toggle Behavior", () => {
    it("chapter bar starts collapsed", async () => {
      const collapsed = await page.$eval("#chapter-bar", (el) =>
        el.classList.contains("scale-y-0")
      );
      assert.ok(collapsed, "Chapter bar should start collapsed (scale-y-0)");
    });

    it("clicking chapter indicator opens the bar", async () => {
      await showPill(page);
      await page.click("#chapter-indicator");
      await sleep(300); // wait for animation

      const open = await page.$eval("#chapter-bar", (el) =>
        el.classList.contains("opacity-100")
      );
      assert.ok(open, "Chapter bar should be visible after clicking indicator");
    });

    it("clicking indicator again closes the bar", async () => {
      await page.click("#chapter-indicator");
      await sleep(300);

      const closed = await page.$eval("#chapter-bar", (el) =>
        el.classList.contains("scale-y-0")
      );
      assert.ok(closed, "Chapter bar should collapse on second click");
    });

    it("clicking outside closes the bar", async () => {
      // Open it
      await showPill(page);
      await page.click("#chapter-indicator");
      await sleep(300);

      // Click outside (on the reader content area)
      await page.click("#reader-content");
      await sleep(300);

      const closed = await page.$eval("#chapter-bar", (el) =>
        el.classList.contains("scale-y-0")
      );
      assert.ok(closed, "Chapter bar should close when clicking outside");
    });
  });

  describe("Scrubber", () => {
    it("scrubber track and thumb exist", async () => {
      const fill = await page.$("[data-scrubber-fill]");
      const thumb = await page.$("[data-scrubber-thumb]");
      assert.ok(fill, "Scrubber fill should exist");
      assert.ok(thumb, "Scrubber thumb should exist");
    });

    it("scrubber position reflects current chapter", async () => {
      const currentIdx = await page.$eval("#chapter-bar", (el) =>
        parseInt(el.dataset.currentIndex)
      );
      const totalChapters = await page.$eval("#chapter-bar", (el) =>
        parseInt(el.dataset.totalChapters)
      );

      const expectedPct =
        totalChapters > 1
          ? (currentIdx / (totalChapters - 1)) * 100
          : 0;

      const fillWidth = await page.$eval("[data-scrubber-fill]", (el) =>
        parseFloat(el.style.width)
      );
      assert.ok(
        Math.abs(fillWidth - expectedPct) < 1,
        `Scrubber fill should be ~${expectedPct}%, got ${fillWidth}%`
      );
    });
  });

  describe("Chapter Strip", () => {
    it("chapter pills exist for each chapter", async () => {
      const chapters = await getChapters(page);
      const pills = await page.$$("[data-chapter-pill]");
      assert.strictEqual(
        pills.length,
        chapters.length,
        `Should have ${chapters.length} chapter pills, got ${pills.length}`
      );
    });

    it("current chapter pill is highlighted", async () => {
      const currentIdx = await page.$eval("#chapter-bar", (el) =>
        parseInt(el.dataset.currentIndex)
      );
      const isHighlighted = await page.$eval(
        `[data-chapter-pill="${currentIdx}"]`,
        (el) => el.classList.contains("bg-primary")
      );
      assert.ok(isHighlighted, "Current chapter pill should have bg-primary");
    });

    it("strip is horizontally scrollable", async () => {
      const hasScrollbar = await page.$eval(
        "[data-chapter-strip]",
        (el) => el.classList.contains("overflow-x-auto")
      );
      assert.ok(hasScrollbar, "Strip should have overflow-x-auto");
    });
  });
});
