/**
 * Standalone Cloud Run Function with OpenTelemetry (no separate instrumentation file)
 * This can be deployed directly via Cloud Console
 */
'use strict';

// Initialize OpenTelemetry FIRST before any other requires
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { Resource } = require('@opentelemetry/resources');
const { ATTR_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');

const sdk = new NodeSDK({
  resource: new Resource({
    [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'otel-api-function',
  }),
  traceExporter: new OTLPTraceExporter(),
  instrumentations: [getNodeAutoInstrumentations()],
});
sdk.start();

// Now import other modules
const functions = require('@google-cloud/functions-framework');
const { trace } = require('@opentelemetry/api');

// Mock data
const USERS = [
  { id: 1, name: 'Alice', email: 'alice@example.com' },
  { id: 2, name: 'Bob', email: 'bob@example.com' },
  { id: 3, name: 'Charlie', email: 'charlie@example.com' },
];

const ORDERS = [
  { id: 101, userId: 1, total: 99.99, status: 'completed' },
  { id: 102, userId: 2, total: 149.50, status: 'pending' },
  { id: 103, userId: 1, total: 25.00, status: 'shipped' },
];

/**
 * Match a URL path against a route pattern
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
 * HTTP Function with multiple routes
 * Entry point: helloHttp
 */
functions.http('helloHttp', (req, res) => {
  const path = req.path || '/';
  const method = req.method;

  // Route patterns
  const routes = [
    { method: 'GET', pattern: '/' },
    { method: 'GET', pattern: '/users' },
    { method: 'GET', pattern: '/users/:id' },
    { method: 'GET', pattern: '/users/:id/orders' },
    { method: 'GET', pattern: '/orders/:id' },
  ];

  // Find matching route
  let httpRoute = path;
  let params = {};
  for (const route of routes) {
    if (route.method !== method) continue;
    const result = matchRoute(route.pattern, path);
    if (result.match) {
      httpRoute = route.pattern;
      params = result.params;
      break;
    }
  }

  // Update auto-instrumented span with parameterized route
  const span = trace.getActiveSpan();
  if (span) {
    span.setAttribute('http.route', httpRoute);
    span.updateName(`${method} ${httpRoute}`);
  }

  // Handle routes
  if (method === 'GET' && path === '/') {
    return res.json({
      service: 'OTel API Function',
      version: '1.0.0',
      routes: ['/users', '/users/:id', '/users/:id/orders', '/orders/:id'],
    });
  }

  if (method === 'GET' && path === '/users') {
    return res.json({ users: USERS });
  }

  if (method === 'GET' && httpRoute === '/users/:id' && !path.includes('/orders')) {
    const user = USERS.find(u => u.id === parseInt(params.id));
    if (!user) return res.status(404).json({ error: 'User not found' });
    return res.json({ user });
  }

  if (method === 'GET' && httpRoute === '/users/:id/orders') {
    const userId = parseInt(params.id);
    const user = USERS.find(u => u.id === userId);
    if (!user) return res.status(404).json({ error: 'User not found' });
    const userOrders = ORDERS.filter(o => o.userId === userId);
    return res.json({ user: { id: user.id, name: user.name }, orders: userOrders });
  }

  if (method === 'GET' && httpRoute === '/orders/:id') {
    const order = ORDERS.find(o => o.id === parseInt(params.id));
    if (!order) return res.status(404).json({ error: 'Order not found' });
    return res.json({ order });
  }

  res.status(404).json({ error: 'Not found', path, method });
});
