interface Topbar {
  config(opts: {
    barColors?: Record<string, string>;
    shadowColor?: string;
  }): void;
  show(delayMs?: number): void;
  hide(): void;
}
declare const topbar: Topbar;
export default topbar;
