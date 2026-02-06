/**
 * Node 10 Express Application
 * OpenTelemetry instrumentation loaded via -r flag
 */

'use strict';

const express = require('express');
const http = require('http');
const https = require('https');
const opentelemetry = require('@opentelemetry/api');

const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// Routes

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'node10-express-example',
    node: process.version,
    otel: '0.25.0',
    timestamp: new Date().toISOString(),
  });
});

// Simple route
app.get('/', (req, res) => {
  res.json({
    message: 'Hello from Node 10 with OpenTelemetry!',
    node: process.version,
    trace_id: getCurrentTraceId(),
  });
});

// Route with custom span
app.get('/custom-span', (req, res) => {
  const tracer = opentelemetry.trace.getTracer('node10-express-example');

  const span = tracer.startSpan('custom-operation');
  span.setAttribute('operation.name', 'custom-span-example');
  span.setAttribute('user.id', '12345');

  // Simulate some work
  setTimeout(() => {
    span.addEvent('Work completed');
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });
    span.end();

    res.json({
      message: 'Custom span created',
      trace_id: getCurrentTraceId(),
    });
  }, 100);
});

// Route that makes external HTTP call
app.get('/external-call', (req, res) => {
  const url = 'https://jsonplaceholder.typicode.com/todos/1';

  https.get(url, (response) => {
    let data = '';

    response.on('data', (chunk) => {
      data += chunk;
    });

    response.on('end', () => {
      res.json({
        message: 'External API called',
        data: JSON.parse(data),
        trace_id: getCurrentTraceId(),
      });
    });
  }).on('error', (error) => {
    res.status(500).json({
      error: error.message,
      trace_id: getCurrentTraceId(),
    });
  });
});

// Route with error
app.get('/error', (req, res) => {
  const tracer = opentelemetry.trace.getTracer('node10-express-example');

  const span = tracer.startSpan('error-operation');
  span.setAttribute('operation.name', 'intentional-error');

  try {
    throw new Error('This is an intentional error for testing');
  } catch (error) {
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message,
    });
    span.end();

    res.status(500).json({
      error: error.message,
      trace_id: getCurrentTraceId(),
    });
  }
});

// Route with query parameter
app.get('/users/:id', (req, res) => {
  const userId = req.params.id;

  const tracer = opentelemetry.trace.getTracer('node10-express-example');
  const span = tracer.startSpan('get-user');
  span.setAttribute('user.id', userId);

  // Simulate database query
  setTimeout(() => {
    span.addEvent('User fetched from database');
    span.end();

    res.json({
      id: userId,
      name: `User ${userId}`,
      email: `user${userId}@example.com`,
      trace_id: getCurrentTraceId(),
    });
  }, 50);
});

// Slow route to test long-running requests
app.get('/slow', (req, res) => {
  const delay = parseInt(req.query.delay) || 2000;

  setTimeout(() => {
    res.json({
      message: `Delayed response after ${delay}ms`,
      trace_id: getCurrentTraceId(),
    });
  }, delay);
});

// Helper function to get current trace ID
function getCurrentTraceId() {
  const span = opentelemetry.trace.getSpan(opentelemetry.context.active());
  if (span) {
    const context = span.spanContext();
    return context.traceId;
  }
  return null;
}

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    path: req.path,
    trace_id: getCurrentTraceId(),
  });
});

// Error handler
app.use((err, req, res, next) => {
  console.error('Express error:', err);
  res.status(500).json({
    error: 'Internal Server Error',
    message: err.message,
    trace_id: getCurrentTraceId(),
  });
});

// Start server
app.listen(port, () => {
  console.log('=================================================');
  console.log(`Express server listening on port ${port}`);
  console.log(`Node version: ${process.version}`);
  console.log('OpenTelemetry: ENABLED (v0.25.0)');
  console.log('=================================================');
  console.log('\nAvailable endpoints:');
  console.log('  GET  /              - Hello endpoint');
  console.log('  GET  /health        - Health check');
  console.log('  GET  /custom-span   - Custom span example');
  console.log('  GET  /external-call - External HTTP call');
  console.log('  GET  /error         - Intentional error');
  console.log('  GET  /users/:id     - User lookup');
  console.log('  GET  /slow?delay=ms - Slow endpoint');
  console.log('=================================================\n');
});
