// Simple in-memory user store for demonstration
const users = [
  { id: '1', name: 'Alice' },
  { id: '2', name: 'Bob' },
];

module.exports = {
  getAllUsers: () => users,
  getUserById: (id) => users.find(u => u.id === id) || null,
  createUser: () => {
    const newUser = { id: String(users.length + 1), name: `User${users.length + 1}` };
    users.push(newUser);
    return newUser;
  },
  updateUser: (id) => {
    const user = users.find(u => u.id === id);
    if (user) user.name = user.name + ' (updated)';
    return user || null;
  },
  deleteUser: (id) => {
    const idx = users.findIndex(u => u.id === id);
    if (idx !== -1) return users.splice(idx, 1)[0];
    return null;
  },
}; 