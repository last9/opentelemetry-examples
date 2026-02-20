// IMPORTANT: Instrumentation must be loaded FIRST before any other modules
require('./instrumentation');

const express = require('express');

const app = express();
app.use(express.json());

/**
 * Final service in the chain
 * Receives requests from Service B
 */
const handleRequest = (req, res) => {
  console.log('[Service C] Received request - Final link in chain');

  res.status(200).json({
    service: 'service-c',
    message: 'Hello from Service C (Final Link in Chain)',
    timestamp: new Date().toISOString()
  });
};

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', service: 'service-c' });
});

// Main endpoint - handles both POST and GET for Cloud Run compatibility
app.post('/', handleRequest);
app.get('/', handleRequest);
app.all('/', handleRequest);

// Export for Cloud Functions compatibility
exports.helloHttp = handleRequest;

// Start server
const PORT = process.env.PORT || 8080;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`[Service C] Listening on port ${PORT}`);
  console.log(`[Service C] Environment: ${process.env.NODE_ENV || 'development'}`);
});
