// services/users.service.js

class UsersService {
  getAllUsers() {
    return 'All users';
  }

  getUserById(id) {
    return `User with id ${id}`;
  }

  createUser() {
    return 'User created';
  }

  updateUser(id) {
    return `User with id ${id} updated`;
  }

  deleteUser(id) {
    return `User with id ${id} deleted`;
  }
}

module.exports = new UsersService();
