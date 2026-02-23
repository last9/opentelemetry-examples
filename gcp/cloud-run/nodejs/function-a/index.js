// IMPORTANT: Instrumentation must be loaded FIRST before any other modules
require('./instrumentation');

const axios = require('axios');
const functions = require('@google-cloud/functions-framework');

/**
 * HTTP Cloud Function that initiates the service chain
 * Function A -> Service B -> Service C
 */
functions.http('startFlow', async (req, res) => {
  console.log('[Function A] Received request to start flow');

  try {
    // Get Service B URL from environment or use default
    const serviceBUrl = process.env.SERVICE_B_URL || 'http://localhost:8082';

    console.log(`[Function A] Calling Service B at: ${serviceBUrl}`);

    // Make request to Service B
    // The OpenTelemetry HTTP instrumentation will automatically:
    // 1. Extract incoming trace context from the request to this function
    // 2. Inject trace context into the outgoing request to Service B
    const response = await axios.post(serviceBUrl, {
      message: 'Request from Function A'
    }, {
      headers: {
        'Content-Type': 'application/json'
      },
      timeout: 30000, // 30 second timeout
    });

    console.log(`[Function A] Received response from Service B: ${response.status}`);

    res.status(200).json({
      service: 'function-a',
      message: 'Chain completed successfully',
      chain: `A -> ${response.data}`,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error(`[Function A] Error in chain: ${error.message}`);
    console.error(`[Function A] Error stack: ${error.stack}`);

    res.status(500).json({
      service: 'function-a',
      error: 'Chain failed',
      message: error.message,
      details: error.response?.data || 'No additional details',
      timestamp: new Date().toISOString()
    });
  }
});
