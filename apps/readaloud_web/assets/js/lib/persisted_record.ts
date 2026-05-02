export class PersistedRecord<T extends object> {
  private current: Readonly<T>;

  constructor(
    private readonly key: string,
    private readonly defaults: Readonly<T>,
    private readonly coerce?: (raw: unknown) => Partial<T>,
  ) {
    this.current = this.read();
  }

  private read(): Readonly<T> {
    const raw = localStorage.getItem(this.key);
    if (!raw) return this.defaults;
    try {
      const parsed = JSON.parse(raw) as unknown;
      const patch = this.coerce ? this.coerce(parsed) : (parsed as Partial<T>);
      return Object.freeze({ ...this.defaults, ...patch });
    } catch {
      return this.defaults;
    }
  }

  get(): Readonly<T> {
    return this.current;
  }

  set(patch: Partial<T>): Readonly<T> {
    this.current = Object.freeze({ ...this.current, ...patch });
    localStorage.setItem(this.key, JSON.stringify(this.current));
    return this.current;
  }
}
