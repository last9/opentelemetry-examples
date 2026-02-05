'use strict';

// Initialize OpenTelemetry FIRST
require('./instrumentation');

const express = require('express');
const https = require('https');
const { trace } = require('@opentelemetry/api');

const app = express();
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'Cloud Run Service with OTel',
    version: process.env.K_REVISION || '1.0.0',
    endpoints: ['/health', '/process', '/chain'],
  });
});

/**
 * Process endpoint - does some work and optionally calls another service
 */
app.get('/process', (req, res) => {
  const span = trace.getActiveSpan();

  // Add custom attributes to the span
  if (span) {
    span.setAttribute('request.query', JSON.stringify(req.query));
    span.setAttribute('process.step', 'processing');
  }

  // Simulate some processing
  const result = {
    processed: true,
    timestamp: new Date().toISOString(),
    query: req.query,
  };

  res.json(result);
});

/**
 * Chain endpoint - calls the Cloud Run Function to demonstrate context propagation
 * The trace context is automatically propagated via traceparent header
 */
app.get('/chain', (req, res) => {
  const functionUrl = process.env.FUNCTION_URL;
  if (!functionUrl) {
    return res.status(500).json({ error: 'FUNCTION_URL environment variable not set' });
  }
  const name = req.query.name || 'ChainedRequest';

  const span = trace.getActiveSpan();
  if (span) {
    span.setAttribute('chain.target', functionUrl);
    span.setAttribute('chain.name', name);
  }

  // Make HTTP request - OTel auto-instrumentation will:
  // 1. Create a child span for this HTTP call
  // 2. Inject traceparent header automatically
  const url = `${functionUrl}/?name=${encodeURIComponent(name)}`;

  https.get(url, (response) => {
    let data = '';
    response.on('data', chunk => data += chunk);
    response.on('end', () => {
      res.json({
        service: 'cloud-run-service',
        calledFunction: functionUrl,
        functionResponse: data,
        traceId: span?.spanContext()?.traceId || 'unknown',
      });
    });
  }).on('error', (err) => {
    if (span) {
      span.setAttribute('error', true);
      span.setAttribute('error.message', err.message);
    }
    res.status(500).json({ error: err.message });
  });
});

/**
 * Multi-hop endpoint - calls function, which could call back to this service
 */
app.post('/multi-hop', (req, res) => {
  const { hops = 1, data = {} } = req.body;
  const span = trace.getActiveSpan();

  if (span) {
    span.setAttribute('multi-hop.remaining', hops);
  }

  if (hops <= 0) {
    return res.json({
      finalHop: true,
      data,
      traceId: span?.spanContext()?.traceId,
    });
  }

  // Continue the chain
  const functionUrl = process.env.FUNCTION_URL;
  if (!functionUrl) {
    return res.status(500).json({ error: 'FUNCTION_URL environment variable not set' });
  }

  const postData = JSON.stringify({
    hops: hops - 1,
    data: { ...data, serviceVisited: true }
  });

  const url = new URL(functionUrl);
  const options = {
    hostname: url.hostname,
    path: '/multi-hop',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(postData),
    },
  };

  const request = https.request(options, (response) => {
    let responseData = '';
    response.on('data', chunk => responseData += chunk);
    response.on('end', () => {
      try {
        res.json(JSON.parse(responseData));
      } catch {
        res.json({ response: responseData });
      }
    });
  });

  request.on('error', (err) => {
    res.status(500).json({ error: err.message });
  });

  request.write(postData);
  request.end();
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Cloud Run Service listening on port ${PORT}`);
});
