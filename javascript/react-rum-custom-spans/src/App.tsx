import { useEffect, useRef, useState } from "react";

import { customSpansSupported, rumReady, rumStatus } from "./rum";

export default function App() {
  const [status, setStatus] = useState("Initializing SDK...");
  const [lines, setLines] = useState<string[]>([]);
  const log = (msg: string) => setLines((l) => [...l, `${new Date().toISOString()} ${msg}`]);

  useEffect(() => {
    rumStatus.then(setStatus);
  }, []);

  // React-idiomatic pattern: a span for a component mount. The ref guard stops StrictMode's
  // double-invoked effect from creating two spans.
  const mounted = useRef(false);
  useEffect(() => {
    if (mounted.current || !customSpansSupported) return;
    mounted.current = true;
    const start = Date.now();
    rumReady.then(() => {
      const ok = window.L9RUM.recordSpan("react.app.mounted", { startTimeMs: start, endTimeMs: Date.now() });
      setLines((l) => [...l, `react.app.mounted sent: ${ok}`]);
    });
  }, []);

  // A finished span: ends now, started durationMs ago.
  const recorded = async () => {
    await rumReady;
    const ok = window.L9RUM.recordSpan("react.recorded", {
      durationMs: 200,
      attributes: { "demo.button": "recorded", "demo.step": 1 },
    });
    log(`react.recorded sent: ${ok}`);
  };

  // A span you end yourself. The SDK records the fetch as its own network span under the same
  // page view, next to react.checkout.
  const checkout = async () => {
    await rumReady;
    const handle = window.L9RUM.startSpan("react.checkout", {
      kind: "client",
      attributes: { "demo.button": "checkout" },
    });
    log("react.checkout started");
    try {
      const res = await fetch("https://httpbin.org/delay/1");
      log(`fetch done: ${res.status}`);
    } catch (err) {
      window.L9RUM.captureError(err, { handled: true, operation: "react.checkout" });
      log(`fetch failed: ${err}`);
    } finally {
      log(`react.checkout ended: ${window.L9RUM.endSpan(handle)}`);
    }
  };

  // Report a handled error. It shows up in Error Tracking with your attributes.
  const error = async () => {
    await rumReady;
    window.L9RUM.captureError(new Error("demo failure"), { handled: true, "demo.button": "error" });
    log("demo failure captured");
  };

  return (
    <main style={{ fontFamily: "system-ui, sans-serif", maxWidth: 640, margin: "2rem auto" }}>
      <h1>Custom spans with Last9 RUM (React)</h1>
      <p>{status}</p>
      <p>
        <button onClick={recorded} disabled={!customSpansSupported}>
          Recorded span
        </button>{" "}
        <button onClick={checkout} disabled={!customSpansSupported}>
          Timed span + fetch
        </button>{" "}
        <button onClick={error}>Handled error</button>
      </p>
      <pre style={{ background: "#f4f4f4", padding: 12, minHeight: 128, overflow: "auto" }}>
        {lines.join("\n")}
      </pre>
    </main>
  );
}
