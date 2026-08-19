// Connectivity snapshot for diagnostic events.
//
// `navigator.onLine` alone can't distinguish a real dead zone from an OS
// background-network restriction: during the 2026-08-18 commute blackout
// Android kept `onLine === true` for six minutes while every fetch()
// threw "Failed to fetch". Pairing it with the Network Information API's
// `effectiveType` (Chromium-only, absent elsewhere) gives the after-the-
// fact reader one more bit — a fetch failing with onLine=true and
// effectiveType="4g" is a Doze-class restriction, not signal loss.

declare global {
  interface Navigator {
    // Network Information API — Chromium/Android only, undefined elsewhere.
    readonly connection?: {
      readonly effectiveType?: string;
    };
  }
}

export interface NetInfo {
  readonly online: boolean | null;
  readonly effectiveType: string | null;
}

export function netInfo(): NetInfo {
  if (typeof navigator === "undefined") {
    return { online: null, effectiveType: null };
  }
  return {
    online: navigator.onLine,
    effectiveType: navigator.connection?.effectiveType ?? null,
  };
}
