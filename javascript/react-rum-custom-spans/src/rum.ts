// Init once at module level, outside any component. Calling it from a useEffect would run it twice
// under <StrictMode> in dev. init() is async and spans started before it resolves are dropped,
// so handlers `await rumReady` before creating spans.
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
