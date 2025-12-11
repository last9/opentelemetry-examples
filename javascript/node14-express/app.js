const express = require('express');
const http = require('http');
const opentelemetry = require('@opentelemetry/api');

const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());

// Helper function to get current trace ID
function getTraceId() {
  const span = opentelemetry.trace.getActiveSpan();
  if (span) {
    return span.spanContext().traceId;
  }
  return null;
}

// 1. Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    traceId: getTraceId(),
  });
});

// 2. Simple hello endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Hello from Node 14 with OpenTelemetry!',
    node: process.version,
    traceId: getTraceId(),
  });
});

// 3. Custom span example
app.get('/custom-span', (req, res) => {
  const tracer = opentelemetry.trace.getTracer('node14-express-example');

  // Create a custom span
  const span = tracer.startSpan('custom-business-logic');
  span.setAttribute('user.action', 'calculate');

  try {
    // Simulate some work
    let result = 0;
    for (let i = 0; i < 1000000; i++) {
      result += i;
    }

    span.setAttribute('calculation.result', result);
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

    res.json({
      message: 'Custom span created',
      result,
      traceId: getTraceId(),
    });
  } catch (error) {
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
    throw error;
  } finally {
    span.end();
  }
});

// 4. External API call (demonstrates HTTP client instrumentation)
app.get('/external-call', async (req, res) => {
  try {
    // Make an HTTP request to external API
    const response = await new Promise((resolve, reject) => {
      http.get('http://jsonplaceholder.typicode.com/posts/1', (resp) => {
        let data = '';
        resp.on('data', (chunk) => { data += chunk; });
        resp.on('end', () => { resolve(JSON.parse(data)); });
      }).on('error', reject);
    });

    res.json({
      message: 'External API call completed',
      data: response,
      traceId: getTraceId(),
    });
  } catch (error) {
    res.status(500).json({
      error: 'External API call failed',
      message: error.message,
      traceId: getTraceId(),
    });
  }
});

// 5. Intentional error endpoint (for error tracking)
app.get('/error', (req, res) => {
  const span = opentelemetry.trace.getActiveSpan();
  const error = new Error('This is an intentional error for testing');

  if (span) {
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
  }

  res.status(500).json({
    error: 'Intentional error',
    message: error.message,
    traceId: getTraceId(),
  });
});

// 6. User lookup endpoint (demonstrates nested spans)
app.get('/users/:id', (req, res) => {
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const userId = req.params.id;

  // Create a span for user lookup
  const lookupSpan = tracer.startSpan('user.lookup');
  lookupSpan.setAttribute('user.id', userId);

  // Simulate database query
  const dbSpan = tracer.startSpan('db.query', {}, opentelemetry.trace.setSpan(opentelemetry.context.active(), lookupSpan));
  dbSpan.setAttribute('db.system', 'postgresql');
  dbSpan.setAttribute('db.statement', `SELECT * FROM users WHERE id = ${userId}`);

  setTimeout(() => {
    dbSpan.end();

    // Simulate user data
    const user = {
      id: userId,
      name: `User ${userId}`,
      email: `user${userId}@example.com`,
    };

    lookupSpan.setAttribute('user.found', true);
    lookupSpan.end();

    res.json({
      user,
      traceId: getTraceId(),
    });
  }, 100);
});

// 7. Slow endpoint (for performance testing)
app.get('/slow', (req, res) => {
  const delay = parseInt(req.query.delay || '1000', 10);

  setTimeout(() => {
    res.json({
      message: `Delayed response after ${delay}ms`,
      traceId: getTraceId(),
    });
  }, delay);
});

// Start server
app.listen(port, () => {
  console.log('========================================');
  console.log(`Node 14 Express + OpenTelemetry Example`);
  console.log('========================================');
  console.log(`Server running on http://localhost:${port}`);
  console.log('');
  console.log('Test Endpoints:');
  console.log(`  GET  http://localhost:${port}/health`);
  console.log(`  GET  http://localhost:${port}/`);
  console.log(`  GET  http://localhost:${port}/custom-span`);
  console.log(`  GET  http://localhost:${port}/external-call`);
  console.log(`  GET  http://localhost:${port}/error`);
  console.log(`  GET  http://localhost:${port}/users/:id`);
  console.log(`  GET  http://localhost:${port}/slow?delay=1000`);
  console.log('========================================\n');
});
