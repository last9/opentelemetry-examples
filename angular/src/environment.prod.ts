export const environment = {
  production: true,

  // OpenTelemetry Configuration for Production
  otel: {
    serviceName: 'your-angular-app',
    // Last9 OTLP endpoint for your organization
    // Format: <your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces
    endpoint: '<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces',
    // Your PRODUCTION Client Token (from Ingestion Tokens page)
    // IMPORTANT: Use a separate token for production with proper origin restrictions!
    apiToken: 'your-production-client-token-here',
    // Production origin (must match token configuration)
    origin: 'https://yourdomain.com',
    // Environment identifier
    environment: 'production'
  }
};
