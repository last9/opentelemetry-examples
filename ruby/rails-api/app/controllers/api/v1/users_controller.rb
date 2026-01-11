module Api
  module V1
    class UsersController < ApplicationController
      SERVICE_NAMESPACE = "users".freeze

      # GET /api/v1/users
      def index
        current_span.set_attribute("users.operation", "list")
        render plain: "success"
      end

      # GET /api/v1/users/:id
      def show
        current_span.set_attribute("users.operation", "get")
        current_span.set_attribute("users.id", params[:id])
        render plain: "success"
      end

      # POST /api/v1/users
      def create
        current_span.set_attribute("users.operation", "create")
        render plain: "success"
      end

      # PUT /api/v1/users/:id
      def update
        current_span.set_attribute("users.operation", "update")
        current_span.set_attribute("users.id", params[:id])
        render plain: "success"
      end

      # DELETE /api/v1/users/:id
      def destroy
        current_span.set_attribute("users.operation", "delete")
        current_span.set_attribute("users.id", params[:id])
        render plain: "success"
      end

      private

      def current_span
        OpenTelemetry::Trace.current_span
      end

      def user_params
        params.require(:user).permit(:name, :email)
      end
    end
  end
end
