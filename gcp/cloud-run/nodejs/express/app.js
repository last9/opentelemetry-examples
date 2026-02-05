/**
 * Cloud Run Express Application with OpenTelemetry
 * Sends traces, logs, and metrics to Last9
 */
'use strict';

const express = require('express');
const { trace, metrics, SpanStatusCode } = require('@opentelemetry/api');
const { logs, SeverityNumber } = require('@opentelemetry/api-logs');

const app = express();
const port = process.env.PORT || 8080;

// Get tracer, meter, and logger
const tracer = trace.getTracer('cloud-run-express');
const meter = metrics.getMeter('cloud-run-express');
const logger = logs.getLogger('cloud-run-express', '1.0.0');

// Create custom metrics
const requestCounter = meter.createCounter('http_requests_total', {
  description: 'Total number of HTTP requests',
  unit: '1',
});

const requestDuration = meter.createHistogram('http_request_duration_seconds', {
  description: 'HTTP request duration in seconds',
  unit: 's',
});

// Middleware
app.use(express.json());

/**
 * Structured logging via OpenTelemetry with trace correlation
 */
function structuredLog(level, message, extra = {}) {
  const span = trace.getActiveSpan();
  const spanContext = span ? span.spanContext() : null;

  // Map string level to SeverityNumber
  const severityMap = {
    'INFO': SeverityNumber.INFO,
    'WARNING': SeverityNumber.WARN,
    'ERROR': SeverityNumber.ERROR,
    'DEBUG': SeverityNumber.DEBUG,
  };

  const severity = severityMap[level] || SeverityNumber.INFO;

  // Emit log via OpenTelemetry
  const logRecord = {
    severityNumber: severity,
    severityText: level,
    body: message,
    attributes: {
      'service.name': process.env.K_SERVICE || 'local',
      'service.revision': process.env.K_REVISION || 'local',
      ...extra,
    },
  };

  // Add trace context if available
  if (spanContext) {
    logRecord.spanId = spanContext.spanId;
    logRecord.traceId = spanContext.traceId;
    logRecord.traceFlags = spanContext.traceFlags;
  }

  logger.emit(logRecord);

  // Also log to console for Cloud Logging (dual output)
  const logEntry = {
    severity: level,
    message,
    timestamp: new Date().toISOString(),
    service: process.env.K_SERVICE || 'local',
    revision: process.env.K_REVISION || 'local',
    ...extra,
  };

  // Add trace correlation for Cloud Logging
  if (spanContext && spanContext.traceId) {
    const projectId = process.env.GOOGLE_CLOUD_PROJECT;
    if (projectId) {
      logEntry['logging.googleapis.com/trace'] = `projects/${projectId}/traces/${spanContext.traceId}`;
      logEntry['logging.googleapis.com/spanId'] = spanContext.spanId;
      logEntry['logging.googleapis.com/trace_sampled'] = (spanContext.traceFlags & 1) === 1;
    }
  }

  console.log(JSON.stringify(logEntry));
}

/**
 * Request timing middleware
 */
app.use((req, res, next) => {
  req.startTime = Date.now();

  res.on('finish', () => {
    const duration = (Date.now() - req.startTime) / 1000;

    // Record metrics
    requestCounter.add(1, {
      'http.method': req.method,
      'http.route': req.route?.path || req.path,
      'http.status_code': res.statusCode,
    });

    requestDuration.record(duration, {
      'http.method': req.method,
      'http.route': req.route?.path || req.path,
    });
  });

  next();
});

/**
 * Routes
 */

// Home endpoint
app.get('/', (req, res) => {
  structuredLog('INFO', 'Home endpoint accessed');
  res.json({
    message: 'Hello from Cloud Run with OpenTelemetry!',
    service: process.env.K_SERVICE || 'local',
    revision: process.env.K_REVISION || 'local',
    nodeVersion: process.version,
  });
});

// Get all users
app.get('/users', (req, res) => {
  const span = tracer.startSpan('fetch_users_from_database', {
    attributes: {
      'db.system': 'postgresql',
      'db.operation': 'SELECT',
    },
  });

  try {
    // Simulate database query
    const users = [
      { id: 1, name: 'Alice', email: 'alice@example.com' },
      { id: 2, name: 'Bob', email: 'bob@example.com' },
      { id: 3, name: 'Charlie', email: 'charlie@example.com' },
    ];

    span.setAttribute('user.count', users.length);
    span.addEvent('Users fetched successfully');
    span.setStatus({ code: SpanStatusCode.OK });

    structuredLog('INFO', `Returning ${users.length} users`);
    res.json(users);
  } catch (error) {
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
    span.recordException(error);
    throw error;
  } finally {
    span.end();
  }
});

// Get user by ID
app.get('/users/:id', (req, res) => {
  const userId = parseInt(req.params.id, 10);

  const span = tracer.startSpan('fetch_user_by_id', {
    attributes: {
      'db.system': 'postgresql',
      'db.operation': 'SELECT',
      'user.id': userId,
    },
  });

  try {
    if (isNaN(userId) || userId <= 0) {
      span.setAttribute('error', true);
      span.setStatus({ code: SpanStatusCode.ERROR, message: 'Invalid user ID' });
      structuredLog('WARNING', `Invalid user ID requested: ${req.params.id}`);
      res.status(400).json({ error: 'Invalid user ID' });
      return;
    }

    // Simulate user lookup
    const user = {
      id: userId,
      name: `User ${userId}`,
      email: `user${userId}@example.com`,
    };

    span.setStatus({ code: SpanStatusCode.OK });
    structuredLog('INFO', `Retrieved user ${userId}`);
    res.json(user);
  } finally {
    span.end();
  }
});

// Create user
app.post('/users', (req, res) => {
  const span = tracer.startSpan('create_user', {
    attributes: {
      'db.system': 'postgresql',
      'db.operation': 'INSERT',
    },
  });

  try {
    const { name, email } = req.body;

    if (!name || !email) {
      span.setAttribute('error', true);
      span.setStatus({ code: SpanStatusCode.ERROR, message: 'Missing required fields' });
      res.status(400).json({ error: 'Name and email are required' });
      return;
    }

    // Simulate user creation
    const newUser = {
      id: Math.floor(Math.random() * 1000) + 100,
      name,
      email,
      createdAt: new Date().toISOString(),
    };

    span.setAttribute('user.id', newUser.id);
    span.addEvent('User created successfully');
    span.setStatus({ code: SpanStatusCode.OK });

    structuredLog('INFO', `Created user ${newUser.id}`, { userName: name });
    res.status(201).json(newUser);
  } finally {
    span.end();
  }
});

// Error test endpoint
app.get('/error', (req, res) => {
  const span = tracer.startSpan('error_operation');

  try {
    // Simulate an error
    throw new Error('This is a simulated error for testing');
  } catch (error) {
    span.setAttribute('error', true);
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });

    structuredLog('ERROR', `Error occurred: ${error.message}`, {
      error: error.message,
      stack: error.stack,
    });

    res.status(500).json({ error: error.message });
  } finally {
    span.end();
  }
});

// Health check (no tracing)
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

// Readiness check
app.get('/ready', (req, res) => {
  res.json({ status: 'ready' });
});

// Start server
app.listen(port, () => {
  structuredLog('INFO', `Server started on port ${port}`, { port });
});

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  structuredLog('ERROR', 'Uncaught exception', {
    error: error.message,
    stack: error.stack,
  });
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  structuredLog('ERROR', 'Unhandled rejection', {
    reason: String(reason),
  });
});
