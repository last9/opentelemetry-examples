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
