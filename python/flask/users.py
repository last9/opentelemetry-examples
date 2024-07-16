from flask import Blueprint, jsonify

users_bp = Blueprint('users', __name__)

@users_bp.route('/', methods=['GET'])
def get_users():
    users = [
        {'id': 1, 'name': 'Alice'},
        {'id': 2, 'name': 'Bob'},
        {'id': 3, 'name': 'Charlie'},
        {'id': 4, 'name': 'David'}
    ]
    return jsonify(users)

@users_bp.route('/<int:user_id>', methods=['GET'])
def get_user(user_id):
    user = {'id': user_id, 'name': f'User {user_id}'}
    return jsonify(user)

@users_bp.route('/', methods=['POST'])
def create_user():
  # Code to create a new user
  return jsonify({'message': 'User created successfully'})

@users_bp.route('/<int:user_id>', methods=['PUT'])
def update_user(user_id):
  # Code to update an existing user
  return jsonify({'message': f'User {user_id} updated successfully'})

@users_bp.route('/<int:user_id>', methods=['DELETE'])
def delete_user(user_id):
  # Code to delete an existing user
  return jsonify({'message': f'User {user_id} deleted successfully'})