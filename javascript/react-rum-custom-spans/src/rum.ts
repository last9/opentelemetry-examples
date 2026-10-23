// Init once at module level, outside any component. init() is async and custom span calls made
// before it resolves return false/null and emit nothing, so handlers `await rumReady` first.
export const rumReady: Promise<void> = window.L9RUM.init({
  baseUrl: import.meta.env.VITE_L9_BASE_URL,
  headers: { clientToken: import.meta.env.VITE_L9_CLIENT_TOKEN },
  resourceAttributes: {
    serviceName: import.meta.env.VITE_L9_SERVICE_NAME || "react-rum-custom-spans",
    deploymentEnvironment: import.meta.env.VITE_L9_ENV || "local",
    appVersion: "1.0.0",
  },
  sampleRate: 100,
  debug: true,
});

// recordSpan/startSpan/endSpan exist from SDK v2.14.0. A browser can keep an older cached copy
// of the stable script; a hard refresh loads the current one.
export const customSpansSupported = typeof window.L9RUM.recordSpan === "function";

export const rumStatus: Promise<string> = customSpansSupported
  ? rumReady.then(() => "SDK ready")
  : Promise.resolve("This app needs Last9 RUM SDK v2.14.0 or later. Hard-refresh to load the current stable SDK.");
