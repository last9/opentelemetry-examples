// IMPORTANT: Tracing must be loaded FIRST before any other modules
require('./tracing');

const express = require('express');
const axios = require('axios');

const app = express();
app.use(express.json());

/**
 * Handler for requests from Service A
 * Forwards the request to Service C
 */
const handleRequest = async (req, res) => {
  console.log('[Service B] Received request');

  try {
    // Get Service C URL from environment or use default
    const serviceCUrl = process.env.SERVICE_C_URL || 'http://localhost:8083';

    console.log(`[Service B] Calling Service C at: ${serviceCUrl}`);

    // Make request to Service C
    // The OpenTelemetry HTTP instrumentation will automatically:
    // 1. Extract incoming trace context from Service A's request
    // 2. Inject trace context into the outgoing request to Service C
    const response = await axios.post(serviceCUrl, {
      message: 'Request from Service B'
    }, {
      headers: {
        'Content-Type': 'application/json'
      },
      timeout: 30000, // 30 second timeout
    });

    console.log(`[Service B] Received response from Service C: ${response.status}`);

    res.status(200).json({
      service: 'service-b',
      message: 'Successfully called Service C',
      chain: `B -> ${response.data}`,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error(`[Service B] Error calling Service C: ${error.message}`);
    console.error(`[Service B] Error stack: ${error.stack}`);

    res.status(500).json({
      service: 'service-b',
      error: 'Failed to call Service C',
      message: error.message,
      details: error.response?.data || 'No additional details',
      timestamp: new Date().toISOString()
    });
  }
};

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', service: 'service-b' });
});

// Main endpoint - handles both POST and GET for Cloud Run compatibility
app.post('/', handleRequest);
app.get('/', handleRequest);

// Export for Cloud Functions compatibility
exports.helloHttp = handleRequest;

// Start server
const PORT = process.env.PORT || 8080;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`[Service B] Listening on port ${PORT}`);
  console.log(`[Service B] Environment: ${process.env.NODE_ENV || 'development'}`);
});
