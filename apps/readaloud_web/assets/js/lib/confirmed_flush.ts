// Confirmed-delivery HTTP flush shared by the progress and player-event
// buffers.
//
// Why this exists: both buffers used to flush with `navigator.sendBeacon`
// and clear their localStorage backlog when it returned `true`. But
// `true` only means the browser QUEUED the request — offline, the beacon
// is silently dropped and the data is gone. The 2026-06-11 incident lost
// its entire offline forensic window (heartbeats, the chapter-ended
// trace, the final progress pivots) to exactly this. Delivery is only
// delivery when the server says 2xx.
//
// Contract: POST the entries in chunks (keepalive requests share a 64KB
// in-flight quota per origin — one big body can be rejected outright),
// resolve with the entries that got a 2xx. Callers remove exactly those
// from their backlog and keep the rest for the next trigger (visibility
// change, network back online, next mount) or until their prune window
// expires them. sendBeacon remains useful as a last-gasp pagehide
// fallback — fired WITHOUT clearing, since its outcome is unknowable.

const FLUSH_CHUNK_SIZE = 100;

export async function flushConfirmed<T>(
  url: string,
  payloadKey: string,
  entries: ReadonlyArray<T>,
): Promise<ReadonlyArray<T>> {
  const delivered: T[] = [];
  for (let i = 0; i < entries.length; i += FLUSH_CHUNK_SIZE) {
    const chunk = entries.slice(i, i + FLUSH_CHUNK_SIZE);
    try {
      const res = await fetch(url, {
        method: "POST",
        keepalive: true,
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ [payloadKey]: chunk }),
      });
      if (!res.ok) break;
      delivered.push(...chunk);
    } catch {
      // Network failure — keep this chunk and everything after it.
      break;
    }
  }
  return delivered;
}

export function beaconBestEffort<T>(
  url: string,
  payloadKey: string,
  entries: ReadonlyArray<T>,
): void {
  if (entries.length === 0) return;
  if (typeof navigator === "undefined" || !navigator.sendBeacon) return;
  const body = new Blob([JSON.stringify({ [payloadKey]: entries })], {
    type: "application/json",
  });
  navigator.sendBeacon(url, body);
}
