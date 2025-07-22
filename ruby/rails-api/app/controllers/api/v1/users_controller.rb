module Api
  module V1
    class UsersController < ApplicationController
      # GET /api/v1/users
      def index
        render plain: "success"
      end

      # GET /api/v1/users/:id
      def show
        render plain: "success"
      end

      # POST /api/v1/users
      def create
        render plain: "success"
      end

      # PUT /api/v1/users/:id
      def update
        render plain: "success"
      end

      # DELETE /api/v1/users/:id
      def destroy
        render plain: "success"
      end

      private

      def user_params
        params.require(:user).permit(:name, :email)
      end
    end
  end
end
