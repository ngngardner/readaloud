// Wedged-socket watchdog for chapter-nav pushEvents.
//
// The reader's chapter text is the one playback replica that can only
// update via a LiveView diff — and a LV socket can be "wedged": open
// enough that pushes buffer instead of failing, but not delivering
// (mobile radio wake-up, post-background recovery). In that state a
// client-owned chapter nav updates audio + URL + persistence instantly
// while the `next_chapter`/`jump_to_chapter` event — and therefore the
// reader text — sits undelivered for tens of seconds (the 2026-06-11
// incident: 23s from pushEvent to server receipt).
//
// LiveView's own protection doesn't cover this window: the channel push
// timeout is 30s and the socket heartbeat is also slow to notice. So:
// arm a timer alongside the push; if no channel-level ack arrives while
// the page is visible, declare the socket wedged and ask app.ts to
// force a disconnect/connect. The reconnect remounts the LV from the
// current URL — which the nav already set via history.pushState — so
// the reader text converges with the audio.
//
// Hidden pages deliberately don't reconnect: timers are throttled, the
// reload guard owns hidden-state recovery, and LV reconnects on its own
// at visibility anyway (remounting from the pushed URL).

export const NAV_ACK_TIMEOUT_MS = 8_000;

export interface NavAckOpts {
  // Performs the pushEvent, wiring the provided callback as its ack.
  readonly push: (onAck: () => void) => void;
  // Called once if no ack arrived within the timeout and the page is
  // visible. Typical implementation: log + dispatch
  // "readaloud:force-reconnect".
  readonly onTimeout: () => void;
}

export function watchNavAck(opts: NavAckOpts): void {
  let acked = false;
  const timer = window.setTimeout(() => {
    if (!acked && document.visibilityState === "visible") {
      opts.onTimeout();
    }
  }, NAV_ACK_TIMEOUT_MS);
  opts.push(() => {
    acked = true;
    window.clearTimeout(timer);
  });
}
