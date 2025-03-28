/**
 * UserController
 *
 * @description :: Server-side actions for handling user requests.
 */

module.exports = {
    /**
     * Get all users
     */
    getAllUsers: async function(req, res) {
      try {
        // Using require to directly access the service
        const UserService = require('../services/UserService');
        const users = await UserService.getAllUsers();
        return res.json(users);
      } catch (error) {
        return res.serverError(error);
      }
    },
  
    /**
     * Get user by ID
     */
    getUserById: async function(req, res) {
      try {
        const userId = req.params.id;
        const UserService = require('../services/UserService');
        const user = await UserService.getUserById(userId);
        return res.json(user);
      } catch (error) {
        if (error.status === 404) {
          return res.notFound(error);
        }
        return res.serverError(error);
      }
    },
  
    /**
     * Create a new user
     */
    createUser: async function(req, res) {
      try {
        const userData = req.body;
        const UserService = require('../services/UserService');
        const newUser = await UserService.createUser(userData);
        return res.status(201).json(newUser);
      } catch (error) {
        return res.serverError(error);
      }
    },
  
    /**
     * Update an existing user
     */
    updateUser: async function(req, res) {
      try {
        const userId = req.params.id;
        const userData = req.body;
        const UserService = require('../services/UserService');
        const updatedUser = await UserService.updateUser(userId, userData);
        return res.json(updatedUser);
      } catch (error) {
        if (error.status === 404) {
          return res.notFound(error);
        }
        return res.serverError(error);
      }
    },
  
    /**
     * Delete a user
     */
    deleteUser: async function(req, res) {
      try {
        const userId = req.params.id;
        const UserService = require('../services/UserService');
        const deletedUser = await UserService.deleteUser(userId);
        return res.json(deletedUser);
      } catch (error) {
        if (error.status === 404) {
          return res.notFound(error);
        }
        return res.serverError(error);
      }
    }
  };