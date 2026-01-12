module Api
  module V1
    class PublicController < ApplicationController
      # NO service.namespace attribute - intentionally omitted for comparison

      # GET /api/v1/public/ping
      def ping
        render json: { pong: true, timestamp: Time.now.iso8601 }
      end

      # GET /api/v1/public/version
      def version
        render json: { version: "1.0.0", rails: Rails.version }
      end

      # GET /api/v1/public/echo
      def echo
        render json: { params: params.to_unsafe_h.except(:controller, :action) }
      end
    end
  end
end
