module Api
  module V1
    class UsersController < ApplicationController
      def index
        render plain: "success"
      end

      def show
        render plain: "success"
      end

      def create
        render plain: "success"
      end

      def update
        render plain: "success"
      end

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
