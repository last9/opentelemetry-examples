# app/controllers/api/v1/user_info_controller.rb
# This controller handles requests related to user information
# It uses the User class from app/lib/user.rb

module Api
  module V1
    class UserInfoController < ApplicationController
      # GET /api/v1/user_info
      # This action creates a User object and returns its details
      def index
        # Step 1: Create a new User object using our lib class
        # This instantiates the User class from app/lib/user.rb
        user = User.new(
          name: "John Doe",
          email: "john.doe@example.com"
        )
        
        # Step 2: Call various methods on the User object
        # Each of these method calls might create separate spans in OpenTelemetry
        full_details = user.full_details
        is_valid = user.valid_email?
        user_hash = user.to_hash
        
        # Step 3: Call the method with sleep to see timing in traces
        processed_data = user.process_user_data
        
        # Step 4: Return JSON response
        render json: {
          success: true,
          full_details: full_details,
          is_valid_email: is_valid,
          user_data: user_hash,
          processed: processed_data
        }
      end
      
      # POST /api/v1/user_info/create
      # This action accepts parameters and creates a User with custom data
      def create
        # Get parameters from the request
        name = params[:name] || "Default User"
        email = params[:email] || "default@example.com"
        
        # Create User with provided parameters
        user = User.new(name: name, email: email)
        
        # Process the user data
        result = user.process_user_data
        
        render json: {
          success: true,
          message: "User created and processed",
          user: user.to_hash,
          processing_result: result
        }, status: :created
      end
      
      # GET /api/v1/user_info/validate
      # This action validates email format
      def validate
        email = params[:email]
        
        if email.blank?
          render json: {
            success: false,
            error: "Email parameter is required"
          }, status: :bad_request
          return
        end
        
        # Create a temporary user to validate email
        user = User.new(name: "Temp", email: email)
        
        render json: {
          success: true,
          email: email,
          is_valid: user.valid_email?,
          details: user.full_details
        }
      end
    end
  end
end
