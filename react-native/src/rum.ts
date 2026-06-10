/**
 * Last9 RUM SDK configuration.
 *
 * Secrets (baseUrl, clientToken, origin) come from a git-ignored `.env`
 * file via Expo's built-in env loading — Expo automatically loads `.env`
 * and exposes any `EXPO_PUBLIC_*` variable on `process.env`. Non-secret
 * identity values are hardcoded here.
 *
 * The actual `L9Rum.initialize(RUM_CONFIG)` call happens at App.tsx module
 * load — before any React useEffect fires — so child screens' useEffects
 * (which run before the App's) hit an initialized SDK and a patched
 * global.fetch.
 */
import type { L9RumConfig } from '@last9/rum-react-native';

export const RUM_CONFIG: L9RumConfig = {
  // --- Required (from .env, loaded by Expo as EXPO_PUBLIC_* vars) ---
  baseUrl: process.env.EXPO_PUBLIC_LAST9_BASE_URL as string,
  clientToken: process.env.EXPO_PUBLIC_LAST9_CLIENT_TOKEN as string,
  origin: process.env.EXPO_PUBLIC_LAST9_ORIGIN as string,

  // --- Identity (hardcoded, non-secret) ---
  serviceName: 'rum-react-native-example',
  serviceVersion: '1.0.0',
  appBuildId: '1.0.0-dev',
  deploymentEnvironment: 'development',

  sampleRate: 100,
  debugLogs: true,

  // Network & error auto-instrumentation
  networkInstrumentation: true,
  nativeNetworkInterception: false,
  ignorePatterns: {
    // Only suppress image/CDN resources; keep public API calls visible in RUM.
    fullUrl: [/^https:\/\/images\.pexels\.com\/photos\//i],
    pathname: [/\.(png|jpe?g|webp)$/i],
    hostname: [/(^|\.)loremflickr\.com$/i],
  },
  propagationMode: 'preserve',
  errorInstrumentation: true,

  // Resource monitoring (CPU/memory)
  resourceMonitoringEnabled: true,
  resourceSamplingIntervalMs: 5000,

  // ANR detection (Android only)
  anrDetectionEnabled: true,
  anrThresholdMs: 5000,

  // Keep network spans on the view's trace so they surface in the
  // Sessions → APIs tab (which filters child spans by the view's traceId).
  isolateTracePerRequest: false,

  // Custom resource attributes
  resourceAttributes: {
    'app.platform': 'react-native',
    'device.type': 'mobile',
  },

  // W3C Baggage propagation
  baggage: {
    enabled: true,
    allowedKeys: [
      'session.id',
      'user.id',
      'deployment.environment',
      'service.name',
    ],
  },
};
