import { SpanStatusCode, trace } from "@opentelemetry/api";
import { useEffect, useRef, useState } from "react";

import { rumReady } from "./rum";

// The SDK registers its tracer provider globally; any @opentelemetry/api 1.x copy finds it via
// Symbol.for("opentelemetry.js.api.1"), so these spans go out through the SDK's exporter.
const tracer = trace.getTracer("react-custom-spans-demo");

const sleep = (ms: number) => new Promise((res) => setTimeout(res, ms));

export default function App() {
  const [lines, setLines] = useState<string[]>([]);
  const log = (msg: string) => setLines((l) => [...l, `${new Date().toISOString()} ${msg}`]);

  // React-idiomatic pattern: a span for a component mount. The ref guard stops StrictMode's
  // double-invoked effect from creating two spans.
  const mounted = useRef(false);
  useEffect(() => {
    if (mounted.current) return;
    mounted.current = true;
    rumReady.then(() => {
      const span = tracer.startSpan("react.app.mounted");
      span.end();
      setLines((l) => [...l, "react.app.mounted ended"]);
    });
  }, []);

  const simple = async () => {
    await rumReady;
    const span = tracer.startSpan("react.simple");
    span.setAttribute("demo.button", "simple");
    span.setAttribute("demo.step", 1);
    log("react.simple started");
    await sleep(200);
    span.end();
    log("react.simple ended");
  };

  const checkout = async () => {
    await rumReady;
    await tracer.startActiveSpan("react.checkout", async (span) => {
      try {
        span.setAttribute("demo.button", "checkout");
        log("react.checkout started");
        await tracer.startActiveSpan("react.checkout.validate", async (child) => {
          await sleep(100);
          child.end();
          log("react.checkout.validate ended");
        });
        const res = await fetch("https://httpbin.org/delay/1");
        span.setAttribute("http.status_code", res.status);
        log(`fetch done: ${res.status}`);
      } catch (err) {
        span.recordException(err as Error);
        span.setStatus({ code: SpanStatusCode.ERROR, message: String(err) });
        log(`react.checkout failed: ${err}`);
      } finally {
        span.end();
        log("react.checkout ended");
      }
    });
  };

  const error = async () => {
    await rumReady;
    const span = tracer.startSpan("react.error");
    span.recordException(new Error("demo failure"));
    span.setStatus({ code: SpanStatusCode.ERROR, message: "demo failure" });
    span.end();
    log("react.error ended with ERROR status");
  };

  return (
    <main style={{ fontFamily: "system-ui, sans-serif", maxWidth: 640, margin: "2rem auto" }}>
      <h1>Custom spans with Last9 RUM (React)</h1>
      <p>
        <button onClick={simple}>Simple span</button>{" "}
        <button onClick={checkout}>Parent span + fetch</button>{" "}
        <button onClick={error}>Error span</button>
      </p>
      <pre style={{ background: "#f4f4f4", padding: 12, minHeight: 128, overflow: "auto" }}>
        {lines.join("\n")}
      </pre>
    </main>
  );
}
