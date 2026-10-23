export {};

type L9SpanKind = "internal" | "client" | "server" | "producer" | "consumer";
type L9Attributes = Record<string, string | number | boolean | string[]>;

declare global {
  interface Window {
    // Loaded from the CDN script tag in index.html. Custom spans need SDK v2.14.0+.
    L9RUM: {
      init(options: Record<string, unknown>): Promise<void>;
      sendTestEvent(): Promise<{ ok: boolean; status: number; spanCount: number; error?: string }>;
      recordSpan(
        name: string,
        options:
          | { durationMs: number; attributes?: L9Attributes; kind?: L9SpanKind }
          | { startTimeMs: number; endTimeMs: number; attributes?: L9Attributes; kind?: L9SpanKind },
      ): boolean;
      startSpan(name: string, options?: { attributes?: L9Attributes; kind?: L9SpanKind }): string | null;
      endSpan(handle: string | null): boolean;
      captureError(error: unknown, attributes?: Record<string, unknown>): void;
    };
  }
}
