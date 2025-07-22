// server.js

// Load environment variables
require('dotenv').config();

const express = require('express');
const bodyParser = require('body-parser');
const morgan = require('morgan');
const usersRoutes = require('./routes/users.routes');
const logger = require('./config/logger');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(morgan('combined', { stream: logger.stream })); // Use Winston for HTTP logging

// Welcome route
app.get('/', (req, res) => {
  logger.info('Welcome route accessed');
  res.json({ message: 'Welcome to the Express API Server!' });
});

// Routes
app.use('/api/users', usersRoutes);

// Error handling middleware
app.use((err, req, res, next) => {
  logger.error('Unhandled error:', { error: err.stack });
  res.status(500).json({ error: 'Something went wrong!' });
});

// Start the server
app.listen(PORT, () => {
  logger.info(`Server running on port ${PORT}`);
});

module.exports = app; // For testing purposes
