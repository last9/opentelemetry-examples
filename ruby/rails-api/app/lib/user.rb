# app/lib/user.rb
# This is a Plain Old Ruby Object (PORO) - just a regular Ruby class
# It's NOT connected to a database (that would be a Model)

class User
  # attr_reader creates getter methods automatically
  # This means we can call user.name and user.email
  # Without this, @name and @email would be private
  attr_reader :name, :email, :created_at
  
  # initialize is called when you do User.new(...)
  # The name: and email: syntax means these are keyword arguments
  def initialize(name:, email:)
    @name = name           # Store name in instance variable
    @email = email         # Store email in instance variable
    @created_at = Time.now # Store when this user object was created
  end
  
  # Custom business logic method #1
  # This returns formatted user details as a string
  def full_details
    "User: #{@name} (#{@email}) - Created at #{@created_at}"
  end
  
  # Custom business logic method #2
  # This validates if the email format is correct
  def valid_email?
    # Check if email contains @ and . symbols
    @email.include?('@') && @email.include?('.')
  end
  
  # Custom business logic method #3
  # This returns a hash representation of the user
  def to_hash
    {
      name: @name,
      email: @email,
      created_at: @created_at,
      is_valid: valid_email?
    }
  end
  
  # Custom business logic method #4
  # Simulate some processing work
  def process_user_data
    sleep(0.1) # Simulate some work (0.1 seconds)
    
    result = {
      processed: true,
      user_name: @name,
      email_valid: valid_email?,
      processing_time: Time.now
    }
    
    result
  end
end
