/**
 * PM2 Ecosystem Configuration for Node.js App with Tail-Based Sampling
 *
 * The app sends traces to a local OTel Collector, which performs
 * tail-based sampling before forwarding to Last9.
 *
 * Setup:
 * 1. Start the collector (see collector-setup.sh)
 * 2. Run: pm2 start ecosystem.config.js
 */

module.exports = {
  apps: [
    {
      name: 'node14-express',
      script: 'app.js',
      node_args: '-r ./instrumentation.js',
      instances: 'max',  // Or specific number like 2
      exec_mode: 'cluster',

      env: {
        NODE_ENV: 'production',
        PORT: 3000,

        // Point to local collector (not directly to Last9)
        OTEL_EXPORTER_OTLP_ENDPOINT: 'http://localhost:4318',

        // No auth headers needed for local collector
        // OTEL_EXPORTER_OTLP_HEADERS is not set

        OTEL_SERVICE_NAME: 'node14-express-example',
        OTEL_RESOURCE_ATTRIBUTES: 'deployment.environment=production',

        // Use always_on - let collector handle sampling
        OTEL_TRACES_SAMPLER: 'always_on',
      },

      // Development environment (direct to Last9, no sampling)
      env_development: {
        NODE_ENV: 'development',
        PORT: 3000,
        OTEL_EXPORTER_OTLP_ENDPOINT: 'https://otlp.last9.io',
        OTEL_EXPORTER_OTLP_HEADERS: 'Authorization=Basic YOUR_TOKEN',
        OTEL_SERVICE_NAME: 'node14-express-example',
        OTEL_TRACES_SAMPLER: 'always_on',
      },
    },
  ],
};
