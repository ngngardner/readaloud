/**
 * Launches ONE shared Chromium for the whole e2e suite and writes its
 * WebSocket endpoint to $WS_ENDPOINT_FILE.
 *
 * node --test runs each test file in its own process, so without this
 * every file pays a full Chromium launch in its before() hook. With it,
 * helpers.setup() sees $BROWSER_WS_ENDPOINT, connects to this browser,
 * and gets a fresh incognito context instead — same isolation
 * (cookies/localStorage are per-context), one launch.
 *
 * Stays alive until SIGTERM/SIGINT (the VM test script stops the unit
 * when the suite is done).
 */
import { writeFileSync } from "node:fs";
import puppeteer from "puppeteer";
import { HEADLESS } from "./helpers.js";

const browser = await puppeteer.launch({
	headless: HEADLESS,
	args: ["--no-sandbox", "--disable-setuid-sandbox"],
});
writeFileSync(process.env.WS_ENDPOINT_FILE, browser.wsEndpoint());

const shutdown = async () => {
	await browser.close();
	process.exit(0);
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
