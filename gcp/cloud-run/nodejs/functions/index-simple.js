'use strict';

// Initialize OpenTelemetry FIRST - before any other requires
require('./instrumentation');

const functions = require('@google-cloud/functions-framework');
const https = require('https');
const { trace } = require('@opentelemetry/api');

/**
 * Simple HTTP function for testing distributed tracing
 */
functions.http('helloHttp', (req, res) => {
  const path = req.path || '/';
  const name = req.query.name || req.body?.name || 'World';

  // Route: /chain - calls the Cloud Run Service to demonstrate context propagation
  if (path === '/chain') {
    const serviceUrl = process.env.SERVICE_URL;
    if (!serviceUrl) {
      return res.status(500).json({ error: 'SERVICE_URL environment variable not set' });
    }
    const span = trace.getActiveSpan();

    if (span) {
      span.setAttribute('chain.target', serviceUrl);
      span.setAttribute('chain.name', name);
    }

    const url = `${serviceUrl}/process?source=function&name=${encodeURIComponent(name)}`;

    https.get(url, (response) => {
      let data = '';
      response.on('data', chunk => data += chunk);
      response.on('end', () => {
        res.json({
          function: 'otel-api-function',
          calledService: serviceUrl,
          serviceResponse: data,
          traceId: span?.spanContext()?.traceId || 'unknown',
        });
      });
    }).on('error', (err) => {
      res.status(500).json({ error: err.message });
    });
    return;
  }

  // Default route: simple hello
  res.send(`Hello ${name}!`);
});
