// server.js
// Load instrumentation first to set up OpenTelemetry
require('./instrumentation');

// Load environment variables
require('dotenv').config();

const fastify = require('fastify')({
  logger: true
});

const usersRoutes = require('./routes/users.routes');

const PORT = process.env.PORT || 3000;

// Welcome route
fastify.get('/', async (request, reply) => {
  return { message: 'Welcome to the Fastify API Server!' };
});

// Register routes
fastify.register(usersRoutes, { prefix: '/api/users' });

// Error handler
fastify.setErrorHandler((error, request, reply) => {
  fastify.log.error('Unhandled error:', error);
  reply.status(500).send({ error: 'Something went wrong!' });
});

// Start the server
const start = async () => {
  try {
    await fastify.listen({ port: PORT });
    console.log(`Server running on port ${PORT}`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};

start();

module.exports = fastify; // For testing purposes
