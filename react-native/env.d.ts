/**
 * Type declarations for the Last9 RUM environment variables.
 *
 * Expo automatically loads `.env` and inlines any `EXPO_PUBLIC_*` variable
 * into `process.env`. (Expo also generates an `expo-env.d.ts` on first run;
 * this file gives `tsc` the typings without needing that generated file.)
 */
declare namespace NodeJS {
  interface ProcessEnv {
    EXPO_PUBLIC_LAST9_BASE_URL: string;
    EXPO_PUBLIC_LAST9_CLIENT_TOKEN: string;
    EXPO_PUBLIC_LAST9_ORIGIN: string;
  }
}
