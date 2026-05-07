import { Notifier, type ReadableStore } from "./store";
import { type JsonValue, parseJson } from "./types";

export class PersistedRecord<T extends object>
  implements ReadableStore<Readonly<T>>
{
  private current: Readonly<T>;
  private readonly notifier = new Notifier<Readonly<T>>();

  // `coerce` is required: it is the narrowing point between an untrusted
  // localStorage blob and a typed `Partial<T>`. Skipping it would force a
  // structural cast at the use-site, defeating the point.
  constructor(
    private readonly key: string,
    private readonly defaults: Readonly<T>,
    private readonly coerce: (raw: JsonValue) => Partial<T>,
  ) {
    this.current = this.read();
  }

  private read(): Readonly<T> {
    const raw = localStorage.getItem(this.key);
    if (!raw) return this.defaults;
    try {
      const patch = this.coerce(parseJson(raw));
      return Object.freeze({ ...this.defaults, ...patch });
    } catch {
      return this.defaults;
    }
  }

  get(): Readonly<T> {
    return this.current;
  }

  set(patch: Partial<T>): void {
    this.current = Object.freeze({ ...this.current, ...patch });
    localStorage.setItem(this.key, JSON.stringify(this.current));
    this.notifier.notify(this.current);
  }

  subscribe(fn: (snapshot: Readonly<T>) => void): () => void {
    return this.notifier.subscribe(fn);
  }
}
