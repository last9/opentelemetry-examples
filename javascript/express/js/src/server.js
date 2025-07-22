// server.js
// Load instrumentation first to set up OpenTelemetry
require('./instrumentation');

// Load environment variables
require('dotenv').config();

const express = require('express');
const bodyParser = require('body-parser');
const morgan = require('morgan');
const usersRoutes = require('./routes/users.routes');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(morgan('dev')); // HTTP request logger

// Welcome route
app.get('/', (req, res) => {
  res.json({ message: 'Welcome to the Express API Server!' });
});

// Routes
app.use('/api/users', usersRoutes);

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// Start the server
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

module.exports = app; // For testing purposes
