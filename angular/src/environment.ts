// This file can be replaced during build by using the `fileReplacements` array.
// `ng build --configuration production` replaces `environment.ts` with `environment.prod.ts`.

export const environment = {
  production: false,

  // OpenTelemetry Configuration
  // These values should be set in your actual environment or loaded from a secure configuration
  otel: {
    serviceName: 'your-angular-app',
    // Last9 OTLP endpoint for your organization
    // Format: <your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces
    endpoint: '<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces',
    // Your Client Token (from Ingestion Tokens page)
    // Get your token from: https://app.last9.io/control-plane/ingestion-tokens
    apiToken: 'your-client-token-here',
    // Allowed origin (must match token configuration)
    origin: 'http://localhost:4200',
    // Environment identifier
    environment: 'development'
  }
};

/*
 * For easier debugging in development mode, you can import the following file
 * to ignore zone related error stack frames such as `zone.run`, `zoneDelegate.invokeTask`.
 */
// import 'zone.js/plugins/zone-error';  // Included with Angular CLI.
