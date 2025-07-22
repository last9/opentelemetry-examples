/**
 * Route Mappings
 * 
 * These routes map URLs to controllers and actions.
 */

module.exports.routes = {
    // User routes
    'GET /api/users': 'UserController.getAllUsers',
    'GET /api/users/:id': 'UserController.getUserById',
    'POST /api/users/create': 'UserController.createUser',
    'PUT /api/users/update/:id': 'UserController.updateUser',
    'DELETE /api/users/delete/:id': 'UserController.deleteUser',
  
    // Health check
    'GET /health': function(req, res) {
      return res.ok('OK');
    },
    
    // Fallback to homepage
    '/': function(req, res) {
      return res.send('Welcome to Sails.js API');
    }
  };