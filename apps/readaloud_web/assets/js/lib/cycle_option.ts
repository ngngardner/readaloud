export function cycleOption<T extends number | string>(
  values: ReadonlyArray<T>,
  current: T,
  direction: "up" | "down",
  eq: (a: T, b: T) => boolean = (a, b) => a === b,
): T {
  const len = values.length;
  if (len === 0) return current;
  const idx = values.findIndex((v) => eq(v, current));
  const base = idx < 0 ? 0 : idx;
  const nextIdx =
    direction === "up" ? (base + 1) % len : (base - 1 + len) % len;
  return values[nextIdx] ?? current;
}
