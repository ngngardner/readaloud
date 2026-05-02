export function cycleOption<T extends number | string>(
  values: ReadonlyArray<T>,
  current: T,
  direction: "up" | "down",
  eq: (a: T, b: T) => boolean = (a, b) => a === b,
): T {
  if (values.length === 0) return current;
  const idx = values.findIndex((v) => eq(v, current));
  const safeIdx = idx < 0 ? 0 : idx;
  const nextIdx =
    direction === "up"
      ? Math.min(values.length - 1, safeIdx + 1)
      : Math.max(0, safeIdx - 1);
  return values[nextIdx] ?? current;
}
