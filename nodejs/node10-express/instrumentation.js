/**
 * OpenTelemetry Instrumentation for Node 10.x
 * Uses OpenTelemetry JS v0.29.2 (Last version supporting Node 10)
 *
 * This file MUST be loaded before any other modules
 */

'use strict';

/**
 * MONKEY-PATCH: Fix gzip compression for Node 10
 *
 * The OTLP exporter reuses a single gzip stream across multiple requests,
 * which causes "Bad Request" / "EOF" errors in Node 10 because the stream
 * state becomes corrupted after first use.
 *
 * This patch directly modifies the util module after loading to ensure
 * a fresh gzip stream is created for each request.
 */
function applyGzipFix() {
  try {
    // Load the util module that contains sendWithHttp
    // Try multiple resolution strategies for robustness
    let utilModule;
    const possiblePaths = [
      '@opentelemetry/otlp-exporter-base/build/src/platform/node/util',
      '@opentelemetry/otlp-exporter-base/build/src/platform/node/util.js',
    ];

    for (const modulePath of possiblePaths) {
      try {
        const resolvedPath = require.resolve(modulePath);
        utilModule = require(resolvedPath);
        if (utilModule && utilModule.sendWithHttp) {
          break;
        }
      } catch (e) {
        // Try next path
      }
    }

    if (!utilModule || !utilModule.sendWithHttp) {
      console.warn('⚠ Could not find sendWithHttp in otlp-exporter-base');
      return false;
    }

    if (utilModule.__node10GzipPatched) {
      return false; // Already patched
    }

    // Load OTLPExporterError for proper error types
    const { OTLPExporterError } = require('@opentelemetry/otlp-exporter-base');
    const { diag } = require('@opentelemetry/api');

    const zlib = require('zlib');
    const { Readable } = require('stream');
    const url = require('url');
    const http = require('http');
    const https = require('https');

    const originalSendWithHttp = utilModule.sendWithHttp;

    utilModule.sendWithHttp = function patchedSendWithHttp(collector, data, contentType, onSuccess, onError) {
      // If compression is NOT gzip, use original function
      if (collector.compression !== 'gzip') {
        return originalSendWithHttp.call(this, collector, data, contentType, onSuccess, onError);
      }

      // Handle gzip ourselves with a FRESH stream each time
      const parsedUrl = new url.URL(collector.url);
      const exporterTimeout = collector.timeoutMillis;
      let reqIsDestroyed = false;

      const options = {
        hostname: parsedUrl.hostname,
        port: parsedUrl.port,
        path: parsedUrl.pathname,
        method: 'POST',
        headers: Object.assign({
          'Content-Type': contentType,
          'Content-Encoding': 'gzip'
        }, collector.headers),
        agent: collector.agent,
      };

      const requestFn = parsedUrl.protocol === 'http:' ? http.request : https.request;
      const req = requestFn(options, (res) => {
        let responseData = '';
        res.on('data', chunk => (responseData += chunk));
        res.on('aborted', () => {
          if (reqIsDestroyed) {
            const err = new OTLPExporterError('Request Timeout');
            onError(err);
          }
        });
        res.on('end', () => {
          if (!reqIsDestroyed) {
            if (res.statusCode && res.statusCode < 299) {
              diag.debug(`statusCode: ${res.statusCode}`, responseData);
              onSuccess();
            } else {
              const error = new OTLPExporterError(res.statusMessage, res.statusCode, responseData);
              onError(error);
            }
            clearTimeout(exporterTimer);
          }
        });
      });

      const exporterTimer = setTimeout(() => {
        reqIsDestroyed = true;
        req.abort();
      }, exporterTimeout);

      req.on('error', (error) => {
        if (reqIsDestroyed) {
          const err = new OTLPExporterError('Request Timeout', error.code);
          onError(err);
        } else {
          clearTimeout(exporterTimer);
          onError(error);
        }
      });

      // THE FIX: Create a FRESH gzip stream for each request
      // Node 10's zlib corrupts stream state when reused
      const gzipStream = zlib.createGzip();
      const dataStream = new Readable();
      dataStream.push(data);
      dataStream.push(null);

      dataStream
        .on('error', onError)
        .pipe(gzipStream)
        .on('error', onError)
        .pipe(req);
    };

    utilModule.__node10GzipPatched = true;
    return true;
  } catch (err) {
    console.warn('⚠ Could not apply Node 10 gzip fix:', err.message);
    return false;
  }
}

// Apply the fix before loading OTel modules
const gzipFixApplied = applyGzipFix();
if (gzipFixApplied) {
  console.log('✓ Applied Node 10 gzip compression fix');
}

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { Resource, envDetector, processDetector, hostDetector } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');

// For debugging, uncomment these lines:
// const { diag, DiagConsoleLogger, DiagLogLevel } = require('@opentelemetry/api');
// diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

console.log('=================================================');
console.log('Initializing OpenTelemetry for Node 10');
console.log('OpenTelemetry Version: 0.29.2');
console.log('Node Version:', process.version);
console.log('=================================================');

// Configuration
const serviceName = process.env.OTEL_SERVICE_NAME || 'node10-express-example';
const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'https://otlp-aps1.last9.io:443';
const headers = process.env.OTEL_EXPORTER_OTLP_HEADERS || '';

// Parse headers
const parsedHeaders = {};
if (headers) {
  headers.split(',').forEach(pair => {
    const [key, ...value] = pair.split('=');
    if (key && value.length) {
      parsedHeaders[key.trim()] = value.join('=').trim();
    }
  });
}

console.log('Service Name:', serviceName);
console.log('Endpoint:', endpoint);

// Initialize NodeSDK with resource detectors
const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: serviceName,
    [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
  }),
  traceExporter: new OTLPTraceExporter({
    url: endpoint.replace(/\/$/, '') + '/v1/traces',
    headers: parsedHeaders,
    compression: 'gzip',
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      // Disable noisy instrumentations
      '@opentelemetry/instrumentation-fs': { enabled: false },
      '@opentelemetry/instrumentation-dns': { enabled: false },
    }),
  ],
  // Resource detectors automatically detect environment metadata
  resourceDetectors: [
    envDetector,         // OTEL_RESOURCE_ATTRIBUTES env var
    processDetector,     // Process info (PID, command, runtime)
    hostDetector,        // Host info (hostname, architecture)
  ],
});

// Start the SDK
try {
  sdk.start();
  console.log('✓ OpenTelemetry SDK started successfully');
  console.log('✓ Auto-instrumentation enabled for:');
  console.log('  - HTTP/HTTPS');
  console.log('  - Express');
  console.log('  - Database drivers (pg, mysql, mongodb, redis)');
  console.log('=================================================\n');
} catch (error) {
  console.error('✗ Failed to start OpenTelemetry SDK:', error);
  process.exit(1);
}

// Graceful shutdown
const shutdown = () => {
  console.log('\nShutting down OpenTelemetry SDK...');
  sdk.shutdown()
    .then(() => {
      console.log('✓ OpenTelemetry SDK shut down successfully');
      process.exit(0);
    })
    .catch((error) => {
      console.error('✗ Error shutting down OpenTelemetry SDK:', error);
      process.exit(1);
    });
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

module.exports = sdk;
