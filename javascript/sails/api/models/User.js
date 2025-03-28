/**
 * User.js
 *
 * A user model representing users in the system.
 */

module.exports = {
    attributes: {
      username: {
        type: 'string',
        required: true,
        unique: true
      },
      email: {
        type: 'string',
        required: true,
        unique: true,
        isEmail: true
      },
      firstName: {
        type: 'string',
        allowNull: true
      },
      lastName: {
        type: 'string',
        allowNull: true
      },
      // Add a reference to any associated data if needed
      // For example, if users can have posts:
      // posts: {
      //   collection: 'post',
      //   via: 'owner'
      // }
    }
  };