'use strict';

// Initialize OpenTelemetry FIRST - before any other requires
require('./instrumentation');

const functions = require('@google-cloud/functions-framework');
const https = require('https');
const { trace } = require('@opentelemetry/api');

/**
 * Helper to make HTTPS GET request
 */
function httpsGet(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (response) => {
      let data = '';
      response.on('data', chunk => data += chunk);
      response.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

/**
 * Simple HTTP function for testing distributed tracing
 *
 * Routes:
 *   GET /                  - Simple hello response
 *   GET /chain             - Calls Cloud Run Service (SERVICE_URL)
 *   GET /call-function     - Calls another function (FUNCTION_URL)
 */
functions.http('helloHttp', async (req, res) => {
  const path = req.path || '/';
  const name = req.query.name || req.body?.name || 'World';
  const span = trace.getActiveSpan();

  try {
    // Route: /call-function - calls another Cloud Run Function
    if (path === '/call-function') {
      const functionUrl = process.env.FUNCTION_URL;
      if (!functionUrl) {
        return res.status(500).json({ error: 'FUNCTION_URL environment variable not set' });
      }

      if (span) {
        span.setAttribute('chain.target', functionUrl);
        span.setAttribute('chain.type', 'function-to-function');
        span.setAttribute('chain.name', name);
      }

      const url = `${functionUrl}/?name=${encodeURIComponent(name)}-from-function`;
      const response = await httpsGet(url);

      return res.json({
        source: 'otel-api-function',
        calledFunction: functionUrl,
        functionResponse: response,
        traceId: span?.spanContext()?.traceId || 'unknown',
      });
    }

    // Route: /chain - calls the Cloud Run Service
    if (path === '/chain') {
      const serviceUrl = process.env.SERVICE_URL;
      if (!serviceUrl) {
        return res.status(500).json({ error: 'SERVICE_URL environment variable not set' });
      }

      if (span) {
        span.setAttribute('chain.target', serviceUrl);
        span.setAttribute('chain.type', 'function-to-service');
        span.setAttribute('chain.name', name);
      }

      const url = `${serviceUrl}/process?source=function&name=${encodeURIComponent(name)}`;
      const response = await httpsGet(url);

      return res.json({
        source: 'otel-api-function',
        calledService: serviceUrl,
        serviceResponse: response,
        traceId: span?.spanContext()?.traceId || 'unknown',
      });
    }

    // Route: / - info endpoint
    if (path === '/') {
      return res.json({
        function: 'otel-api-function',
        message: `Hello ${name}!`,
        routes: ['GET /', 'GET /chain', 'GET /call-function'],
        traceId: span?.spanContext()?.traceId || 'unknown',
      });
    }

    // Default: simple hello for any other path
    res.send(`Hello ${name}!`);
  } catch (err) {
    if (span) {
      span.setAttribute('error', true);
      span.setAttribute('error.message', err.message);
    }
    res.status(500).json({ error: err.message });
  }
});
