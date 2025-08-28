# app.rb
require 'sinatra'
require 'dotenv/load'

require_relative 'instrumentation'

users = [
  { id: 1, name: 'John Doe' },
  { id: 2, name: 'Jane Smith' },
  { id: 3, name: 'Bob Johnson' }
]

# Get all users
get '/api/users' do
  users.to_json
end

# Create a new user
post '/api/users' do
  new_user = { id: users.length + 1, name: params[:name] }
  users << new_user
  new_user.to_json
end

# Read a user
get '/api/users/:id' do
  user = users.find { |user| user[:id] == params[:id].to_i }
  user.to_json
end

# Update a user
put '/api/users/:id' do
  user = users.find { |user| user[:id] == params[:id].to_i }
  if user
    user[:name] = params[:name]
    user.to_json
  else
    status 404
    'User not found'
  end
end

# Delete a user
delete '/api/users/:id' do
  user = users.find { |user| user[:id] == params[:id].to_i }
  if user
    users.delete(user)
    user.to_json
  else
    status 404
    'User not found'
  end
end

not_found do
  status 404
  'Page not found'
end
