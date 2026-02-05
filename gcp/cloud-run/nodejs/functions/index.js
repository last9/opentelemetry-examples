/**
 * Cloud Run Functions with OpenTelemetry instrumentation
 *
 * This file exports multiple function handlers that can be deployed separately.
 * Each function is instrumented with OpenTelemetry for traces, metrics, and logs.
 */
'use strict';

const functions = require('@google-cloud/functions-framework');
const { trace, SpanStatusCode, metrics } = require('@opentelemetry/api');
const { logs, SeverityNumber } = require('@opentelemetry/api-logs');

// Get tracer and meter for custom instrumentation
const tracer = trace.getTracer('cloud-run-functions', '1.0.0');
const meter = metrics.getMeter('cloud-run-functions', '1.0.0');
const logger = logs.getLogger('cloud-run-functions', '1.0.0');

// Custom metrics
const requestCounter = meter.createCounter('function_invocations_total', {
  description: 'Total number of function invocations',
});

const requestDuration = meter.createHistogram('function_duration_seconds', {
  description: 'Function execution duration in seconds',
  unit: 's',
});

/**
 * Structured logging with trace correlation
 */
function structuredLog(level, message, extra = {}) {
  const span = trace.getActiveSpan();
  const spanContext = span ? span.spanContext() : null;

  const severityMap = {
    DEBUG: SeverityNumber.DEBUG,
    INFO: SeverityNumber.INFO,
    WARN: SeverityNumber.WARN,
    ERROR: SeverityNumber.ERROR,
  };

  // Emit log via OpenTelemetry
  const logRecord = {
    severityNumber: severityMap[level] || SeverityNumber.INFO,
    severityText: level,
    body: message,
    attributes: extra,
  };

  if (spanContext) {
    logRecord.spanId = spanContext.spanId;
    logRecord.traceId = spanContext.traceId;
    logRecord.traceFlags = spanContext.traceFlags;
  }

  logger.emit(logRecord);

  // Also log to console for Cloud Logging
  const logEntry = {
    severity: level,
    message,
    timestamp: new Date().toISOString(),
    ...extra,
  };

  if (spanContext && spanContext.traceId) {
    const projectId = process.env.GOOGLE_CLOUD_PROJECT;
    if (projectId) {
      logEntry['logging.googleapis.com/trace'] = `projects/${projectId}/traces/${spanContext.traceId}`;
      logEntry['logging.googleapis.com/spanId'] = spanContext.spanId;
    }
  }

  console.log(JSON.stringify(logEntry));
}

/**
 * HTTP Function: Hello World
 * A simple HTTP function that demonstrates basic tracing
 *
 * Deploy with: gcloud functions deploy helloHttp --gen2 --runtime=nodejs20 ...
 */
functions.http('helloHttp', async (req, res) => {
  const startTime = Date.now();
  const functionName = 'helloHttp';

  requestCounter.add(1, {
    function: functionName,
    method: req.method,
  });

  structuredLog('INFO', 'Function invoked', {
    function: functionName,
    method: req.method,
    path: req.path,
  });

  try {
    // Get name from query param or request body
    const name = req.query.name || req.body?.name || 'World';

    // Create a custom span for business logic
    const result = await tracer.startActiveSpan('processGreeting', async (span) => {
      span.setAttribute('greeting.name', name);

      // Simulate some processing
      await simulateWork(50);

      const greeting = `Hello, ${name}! Processed by Cloud Run Functions with OpenTelemetry.`;

      span.setStatus({ code: SpanStatusCode.OK });
      span.end();

      return greeting;
    });

    const duration = (Date.now() - startTime) / 1000;
    requestDuration.record(duration, { function: functionName, status: 'success' });

    structuredLog('INFO', 'Function completed successfully', {
      function: functionName,
      durationMs: Date.now() - startTime,
    });

    res.status(200).json({
      message: result,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    const duration = (Date.now() - startTime) / 1000;
    requestDuration.record(duration, { function: functionName, status: 'error' });

    structuredLog('ERROR', 'Function failed', {
      function: functionName,
      error: error.message,
    });

    res.status(500).json({ error: error.message });
  }
});

/**
 * HTTP Function: Process Data
 * Demonstrates more complex processing with multiple spans
 *
 * Deploy with: gcloud functions deploy processData --gen2 --runtime=nodejs20 ...
 */
functions.http('processData', async (req, res) => {
  const startTime = Date.now();
  const functionName = 'processData';

  requestCounter.add(1, {
    function: functionName,
    method: req.method,
  });

  // Only accept POST requests
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  structuredLog('INFO', 'Processing data request', {
    function: functionName,
    contentType: req.headers['content-type'],
  });

  try {
    const data = req.body;

    if (!data || Object.keys(data).length === 0) {
      res.status(400).json({ error: 'Request body is required' });
      return;
    }

    // Process data with multiple traced operations
    const result = await tracer.startActiveSpan('processDataPipeline', async (pipelineSpan) => {
      pipelineSpan.setAttribute('data.keys', Object.keys(data).length);

      // Step 1: Validate
      const validated = await tracer.startActiveSpan('validateData', async (span) => {
        span.setAttribute('validation.type', 'schema');
        await simulateWork(20);
        span.setStatus({ code: SpanStatusCode.OK });
        span.end();
        return { ...data, validated: true };
      });

      // Step 2: Transform
      const transformed = await tracer.startActiveSpan('transformData', async (span) => {
        span.setAttribute('transform.type', 'normalize');
        await simulateWork(30);
        const result = {
          ...validated,
          transformed: true,
          processedAt: new Date().toISOString(),
        };
        span.setStatus({ code: SpanStatusCode.OK });
        span.end();
        return result;
      });

      // Step 3: Enrich (simulated external call)
      const enriched = await tracer.startActiveSpan('enrichData', async (span) => {
        span.setAttribute('enrichment.source', 'internal');
        await simulateWork(40);
        const result = {
          ...transformed,
          enriched: true,
          metadata: {
            processedBy: 'cloud-run-functions',
            version: '1.0.0',
          },
        };
        span.setStatus({ code: SpanStatusCode.OK });
        span.end();
        return result;
      });

      pipelineSpan.setStatus({ code: SpanStatusCode.OK });
      pipelineSpan.end();

      return enriched;
    });

    const duration = (Date.now() - startTime) / 1000;
    requestDuration.record(duration, { function: functionName, status: 'success' });

    structuredLog('INFO', 'Data processing completed', {
      function: functionName,
      durationMs: Date.now() - startTime,
    });

    res.status(200).json({
      success: true,
      result,
    });
  } catch (error) {
    const duration = (Date.now() - startTime) / 1000;
    requestDuration.record(duration, { function: functionName, status: 'error' });

    structuredLog('ERROR', 'Data processing failed', {
      function: functionName,
      error: error.message,
    });

    res.status(500).json({ error: error.message });
  }
});

/**
 * CloudEvent Function: Handle Pub/Sub messages
 * Triggered by Pub/Sub messages via CloudEvents
 *
 * Deploy with:
 * gcloud functions deploy handlePubSub --gen2 --runtime=nodejs20 \
 *   --trigger-topic=YOUR_TOPIC ...
 */
functions.cloudEvent('handlePubSub', async (cloudEvent) => {
  const startTime = Date.now();
  const functionName = 'handlePubSub';

  requestCounter.add(1, {
    function: functionName,
    trigger: 'pubsub',
  });

  return tracer.startActiveSpan('handlePubSubMessage', async (span) => {
    try {
      // Extract message data
      const messageData = cloudEvent.data?.message?.data;
      const messageId = cloudEvent.data?.message?.messageId || cloudEvent.id;

      span.setAttribute('messaging.system', 'gcp_pubsub');
      span.setAttribute('messaging.message_id', messageId);
      span.setAttribute('messaging.destination', cloudEvent.source || 'unknown');

      structuredLog('INFO', 'Processing Pub/Sub message', {
        function: functionName,
        messageId,
        eventType: cloudEvent.type,
      });

      // Decode message if base64 encoded
      let decodedMessage = '';
      if (messageData) {
        decodedMessage = Buffer.from(messageData, 'base64').toString('utf-8');
        span.setAttribute('messaging.message_payload_size_bytes', decodedMessage.length);
      }

      structuredLog('DEBUG', 'Message content', {
        function: functionName,
        messageId,
        content: decodedMessage.substring(0, 100), // Log first 100 chars
      });

      // Process the message (add your business logic here)
      await tracer.startActiveSpan('processMessage', async (processSpan) => {
        processSpan.setAttribute('message.length', decodedMessage.length);
        await simulateWork(100);
        processSpan.setStatus({ code: SpanStatusCode.OK });
        processSpan.end();
      });

      const duration = (Date.now() - startTime) / 1000;
      requestDuration.record(duration, { function: functionName, status: 'success' });

      structuredLog('INFO', 'Pub/Sub message processed successfully', {
        function: functionName,
        messageId,
        durationMs: Date.now() - startTime,
      });

      span.setStatus({ code: SpanStatusCode.OK });
    } catch (error) {
      const duration = (Date.now() - startTime) / 1000;
      requestDuration.record(duration, { function: functionName, status: 'error' });

      structuredLog('ERROR', 'Failed to process Pub/Sub message', {
        function: functionName,
        error: error.message,
      });

      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error.message,
      });
      span.recordException(error);

      // Re-throw to trigger retry if needed
      throw error;
    } finally {
      span.end();
    }
  });
});

/**
 * CloudEvent Function: Handle Cloud Storage events
 * Triggered when objects are created/deleted in a bucket
 *
 * Deploy with:
 * gcloud functions deploy handleStorage --gen2 --runtime=nodejs20 \
 *   --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
 *   --trigger-event-filters="bucket=YOUR_BUCKET" ...
 */
functions.cloudEvent('handleStorage', async (cloudEvent) => {
  const startTime = Date.now();
  const functionName = 'handleStorage';

  requestCounter.add(1, {
    function: functionName,
    trigger: 'storage',
  });

  return tracer.startActiveSpan('handleStorageEvent', async (span) => {
    try {
      const file = cloudEvent.data;

      span.setAttribute('cloud.storage.bucket', file.bucket);
      span.setAttribute('cloud.storage.object', file.name);
      span.setAttribute('cloud.storage.event_type', cloudEvent.type);

      structuredLog('INFO', 'Processing Cloud Storage event', {
        function: functionName,
        bucket: file.bucket,
        object: file.name,
        eventType: cloudEvent.type,
        contentType: file.contentType,
        size: file.size,
      });

      // Process the file (add your business logic here)
      await tracer.startActiveSpan('processFile', async (processSpan) => {
        processSpan.setAttribute('file.size', file.size || 0);
        processSpan.setAttribute('file.content_type', file.contentType || 'unknown');
        await simulateWork(150);
        processSpan.setStatus({ code: SpanStatusCode.OK });
        processSpan.end();
      });

      const duration = (Date.now() - startTime) / 1000;
      requestDuration.record(duration, { function: functionName, status: 'success' });

      structuredLog('INFO', 'Cloud Storage event processed successfully', {
        function: functionName,
        bucket: file.bucket,
        object: file.name,
        durationMs: Date.now() - startTime,
      });

      span.setStatus({ code: SpanStatusCode.OK });
    } catch (error) {
      const duration = (Date.now() - startTime) / 1000;
      requestDuration.record(duration, { function: functionName, status: 'error' });

      structuredLog('ERROR', 'Failed to process Cloud Storage event', {
        function: functionName,
        error: error.message,
      });

      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error.message,
      });
      span.recordException(error);
      throw error;
    } finally {
      span.end();
    }
  });
});

/**
 * Simulate async work (for demo purposes)
 */
function simulateWork(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ============================================================================
// Mock data for API demo
// ============================================================================

const USERS = [
  { id: 1, name: 'Alice Johnson', email: 'alice@example.com', role: 'admin' },
  { id: 2, name: 'Bob Smith', email: 'bob@example.com', role: 'user' },
  { id: 3, name: 'Charlie Brown', email: 'charlie@example.com', role: 'user' },
  { id: 4, name: 'Diana Prince', email: 'diana@example.com', role: 'moderator' },
  { id: 5, name: 'Eve Wilson', email: 'eve@example.com', role: 'user' },
];

const ORDERS = [
  { id: 101, userId: 1, total: 99.99, status: 'completed', items: 3 },
  { id: 102, userId: 2, total: 149.50, status: 'pending', items: 5 },
  { id: 103, userId: 1, total: 25.00, status: 'shipped', items: 1 },
  { id: 104, userId: 3, total: 299.99, status: 'completed', items: 2 },
];

const PRODUCTS = [
  { id: 1001, name: 'Widget Pro', price: 49.99, stock: 100 },
  { id: 1002, name: 'Gadget Plus', price: 79.99, stock: 50 },
  { id: 1003, name: 'Tool Kit', price: 129.99, stock: 25 },
];

/**
 * Match a URL path against a route pattern and extract params
 */
function matchRoute(pattern, path) {
  const patternParts = pattern.split('/').filter(Boolean);
  const pathParts = path.split('/').filter(Boolean);

  if (patternParts.length !== pathParts.length) {
    return { match: false, params: {} };
  }

  const params = {};
  for (let i = 0; i < patternParts.length; i++) {
    if (patternParts[i].startsWith(':')) {
      params[patternParts[i].slice(1)] = pathParts[i];
    } else if (patternParts[i] !== pathParts[i]) {
      return { match: false, params: {} };
    }
  }

  return { match: true, params };
}

/**
 * HTTP Function: API with multiple routes
 * Uses auto-instrumentation only - sets http.route for proper trace grouping
 *
 * Routes:
 *   GET  /users               - List all users
 *   GET  /users/:id           - Get user by ID
 *   GET  /users/:id/orders    - Get orders for a user
 *   GET  /orders/:id          - Get order by ID
 *   GET  /products            - List all products
 *   GET  /products/:id        - Get product by ID
 */
functions.http('apiFunction', async (req, res) => {
  const path = req.path || '/';
  const method = req.method;

  // Route patterns for matching
  const routePatterns = [
    { method: 'GET', pattern: '/' },
    { method: 'GET', pattern: '/health' },
    { method: 'GET', pattern: '/users' },
    { method: 'GET', pattern: '/users/:id' },
    { method: 'GET', pattern: '/users/:id/orders' },
    { method: 'GET', pattern: '/orders' },
    { method: 'GET', pattern: '/orders/:id' },
    { method: 'GET', pattern: '/products' },
    { method: 'GET', pattern: '/products/:id' },
    { method: 'POST', pattern: '/orders' },
  ];

  // Find matching route pattern
  let httpRoute = path;
  let params = {};

  for (const route of routePatterns) {
    if (route.method !== method) continue;
    const result = matchRoute(route.pattern, path);
    if (result.match) {
      httpRoute = route.pattern;
      params = result.params;
      break;
    }
  }

  // Update the auto-instrumented span with the parameterized route
  const activeSpan = trace.getActiveSpan();
  if (activeSpan) {
    activeSpan.setAttribute('http.route', httpRoute);
    activeSpan.updateName(`${method} ${httpRoute}`);
  }

  // Route handling
  try {
    // GET /
    if (method === 'GET' && path === '/') {
      return res.json({
        service: 'Cloud Run Functions API',
        version: '1.0.0',
        endpoints: ['GET /users', 'GET /users/:id', 'GET /users/:id/orders', 'GET /orders/:id', 'GET /products', 'GET /products/:id'],
      });
    }

    // GET /health
    if (method === 'GET' && path === '/health') {
      return res.json({ status: 'healthy' });
    }

    // GET /users
    if (method === 'GET' && path === '/users') {
      await simulateWork(30);
      return res.json({ users: USERS, count: USERS.length });
    }

    // GET /users/:id
    if (method === 'GET' && httpRoute === '/users/:id' && !path.includes('/orders')) {
      const userId = parseInt(params.id, 10);
      await simulateWork(20);
      const user = USERS.find((u) => u.id === userId);
      if (!user) return res.status(404).json({ error: `User ${userId} not found` });
      return res.json({ user });
    }

    // GET /users/:id/orders
    if (method === 'GET' && httpRoute === '/users/:id/orders') {
      const userId = parseInt(params.id, 10);
      await simulateWork(25);
      const user = USERS.find((u) => u.id === userId);
      if (!user) return res.status(404).json({ error: `User ${userId} not found` });
      const userOrders = ORDERS.filter((o) => o.userId === userId);
      return res.json({ user: { id: user.id, name: user.name }, orders: userOrders });
    }

    // GET /orders
    if (method === 'GET' && path === '/orders') {
      await simulateWork(30);
      return res.json({ orders: ORDERS, count: ORDERS.length });
    }

    // GET /orders/:id
    if (method === 'GET' && httpRoute === '/orders/:id') {
      const orderId = parseInt(params.id, 10);
      await simulateWork(20);
      const order = ORDERS.find((o) => o.id === orderId);
      if (!order) return res.status(404).json({ error: `Order ${orderId} not found` });
      return res.json({ order });
    }

    // GET /products
    if (method === 'GET' && path === '/products') {
      await simulateWork(25);
      return res.json({ products: PRODUCTS, count: PRODUCTS.length });
    }

    // GET /products/:id
    if (method === 'GET' && httpRoute === '/products/:id') {
      const productId = parseInt(params.id, 10);
      await simulateWork(20);
      const product = PRODUCTS.find((p) => p.id === productId);
      if (!product) return res.status(404).json({ error: `Product ${productId} not found` });
      return res.json({ product });
    }

    // POST /orders
    if (method === 'POST' && path === '/orders') {
      const { userId, items, total } = req.body || {};
      if (!userId || !items || !total) {
        return res.status(400).json({ error: 'Missing required fields: userId, items, total' });
      }
      await simulateWork(50);
      const newOrder = {
        id: Math.floor(Math.random() * 10000) + 1000,
        userId: parseInt(userId, 10),
        items,
        total: parseFloat(total),
        status: 'pending',
        createdAt: new Date().toISOString(),
      };
      return res.status(201).json({ order: newOrder });
    }

    // 404 for unmatched routes
    res.status(404).json({ error: 'Not Found', path, method });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
