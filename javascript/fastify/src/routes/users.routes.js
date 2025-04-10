// routes/users.routes.js
const usersService = require('../services/users.service');

async function routes(fastify, options) {
  // Get all users
  fastify.get('/', async (request, reply) => {
    return usersService.getAllUsers();
  });

  // Get user by ID
  fastify.get('/:id', async (request, reply) => {
    return usersService.getUserById(request.params.id);
  });

  // Create user
  fastify.post('/create', async (request, reply) => {
    return usersService.createUser();
  });

  // Update user
  fastify.put('/update/:id', async (request, reply) => {
    return usersService.updateUser(request.params.id);
  });

  // Delete user
  fastify.delete('/delete/:id', async (request, reply) => {
    return usersService.deleteUser(request.params.id);
  });
}

module.exports = routes;
