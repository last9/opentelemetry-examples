const polka = require('polka');
const usersService = require('../services/users.service');

const app = polka();
const base = '/users';

// Get all users
app.get('/', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(usersService.getAllUsers()));
});

// Get user by ID
app.get('/:id', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(usersService.getUserById(req.params.id)));
});

// Create user
app.post('/create', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(usersService.createUser()));
});

// Update user
app.put('/update/:id', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(usersService.updateUser(req.params.id)));
});

// Delete user
app.delete('/delete/:id', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.end(JSON.stringify(usersService.deleteUser(req.params.id)));
});

module.exports = app; 