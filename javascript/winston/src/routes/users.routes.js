// routes/users.routes.js
const express = require('express');
const router = express.Router();
const usersService = require('../services/users.service');

// Get all users
router.get('/', (req, res) => {
  res.send(usersService.getAllUsers());
});

// Get user by ID
router.get('/:id', (req, res) => {
  res.send(usersService.getUserById(req.params.id));
});

// Create user
router.post('/create', (req, res) => {
  res.send(usersService.createUser());
});

// Update user
router.put('/update/:id', (req, res) => {
  res.send(usersService.updateUser(req.params.id));
});

// Delete user (added to match service functionality)
router.delete('/delete/:id', (req, res) => {
  res.send(usersService.deleteUser(req.params.id));
});

module.exports = router;
