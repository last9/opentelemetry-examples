/**
 * app.js
 *
 * The main entry point for your Sails application.
 */

// First, require our instrumentation to set up OpenTelemetry
require('./instrumentation');

// Load environment variables
require('dotenv').config();

// Then load the Sails framework
const sails = require('sails');
const rc = require('sails/accessible/rc');

// Get configuration (using sails/accessible/rc)
const config = rc('sails');

// Start Sails app
sails.lift(config, (err) => {
  if (err) {
    console.error('Failed to lift Sails app:', err);
    return process.exit(1);
  }

  console.log('Sails app lifted successfully!');
  console.log(`Server running on port ${sails.config.port}`);
});