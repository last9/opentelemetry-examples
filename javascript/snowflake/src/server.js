const path = require('path');
const dotenv = require('dotenv');

// Load environment variables from env/.env
dotenv.config({ path: path.join(__dirname, '..', 'env', '.env') });

// Import OpenTelemetry instrumentation FIRST (before other imports)
require('./instrumentation');

const express = require('express');
const { executeQuery } = require('./snowflake-client');
const { trace } = require('@opentelemetry/api');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'UP',
    service: process.env.OTEL_SERVICE_NAME || 'snowflake-app',
    timestamp: new Date().toISOString()
  });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Snowflake OpenTelemetry Example',
    endpoints: [
      'GET /health - Health check',
      'GET /api/query - Execute a sample SELECT query',
      'POST /api/query - Execute a custom query'
    ]
  });
});

// API endpoint: Execute a sample query with tracing
app.get('/api/query', async (req, res) => {
  const tracer = trace.getTracer('snowflake-api');

  await tracer.startActiveSpan('api.sample-query', async (span) => {
    try {
      span.setAttribute('http.method', 'GET');
      span.setAttribute('http.route', '/api/query');
      span.setAttribute('http.url', req.url);

      // Sample query - modify this to match your Snowflake schema
      const query = 'SELECT CURRENT_TIMESTAMP() as current_time, CURRENT_USER() as current_user';
      const results = await executeQuery(query, 'sample-query');

      span.setAttribute('response.count', results.length);
      span.setAttribute('http.status_code', 200);
      span.setStatus({ code: 1 });

      res.json({
        success: true,
        data: results,
        count: results.length
      });
    } catch (error) {
      span.recordException(error);
      span.setAttribute('http.status_code', 500);
      span.setStatus({ code: 2, message: error.message });

      res.status(500).json({
        success: false,
        error: error.message
      });
    } finally {
      span.end();
    }
  });
});

// API endpoint: Execute a custom query with tracing
app.post('/api/query', async (req, res) => {
  const tracer = trace.getTracer('snowflake-api');
  const { sql, queryName } = req.body;

  if (!sql) {
    return res.status(400).json({
      success: false,
      error: 'SQL query is required in request body'
    });
  }

  await tracer.startActiveSpan('api.custom-query', async (span) => {
    try {
      span.setAttribute('http.method', 'POST');
      span.setAttribute('http.route', '/api/query');
      span.setAttribute('http.url', req.url);
      span.setAttribute('query.name', queryName || 'custom-query');

      const results = await executeQuery(sql, queryName || 'custom-query');

      span.setAttribute('response.count', results.length);
      span.setAttribute('http.status_code', 200);
      span.setStatus({ code: 1 });

      res.json({
        success: true,
        data: results,
        count: results.length
      });
    } catch (error) {
      span.recordException(error);
      span.setAttribute('http.status_code', 500);
      span.setStatus({ code: 2, message: error.message });

      res.status(500).json({
        success: false,
        error: error.message
      });
    } finally {
      span.end();
    }
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Snowflake endpoints: GET /api/query, POST /api/query`);
  console.log(`Health check: GET /health`);
});
