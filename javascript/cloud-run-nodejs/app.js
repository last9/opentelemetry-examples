'use strict';

const express = require('express');
const { logInfo, logWarn, logError, logDebug } = require('./instrumentation');

const app = express();
const PORT = process.env.PORT || 8080;

app.get('/', (req, res) => {
  // These will NOT be sent (filtered out)
  logDebug('Debug: handling request', { path: '/' });
  logInfo('Info: processing request', { path: '/' });
  logWarn('Warn: this is a warning', { path: '/' });

  res.json({ status: 'ok', message: 'Hello from Cloud Run!' });
});

app.get('/error', (req, res) => {
  // This WILL be sent (ERROR level)
  logError('Error: something went wrong', {
    path: '/error',
    errorCode: 'TEST_ERROR'
  });

  res.status(500).json({ status: 'error', message: 'Test error logged' });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log('Test endpoints:');
  console.log(`  http://localhost:${PORT}/       - emits DEBUG, INFO, WARN (filtered)`);
  console.log(`  http://localhost:${PORT}/error  - emits ERROR (will be sent)`);
});
