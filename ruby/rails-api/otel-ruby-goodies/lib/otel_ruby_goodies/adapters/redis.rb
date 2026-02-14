# frozen_string_literal: true

module OTelRubyGoodies
  module Adapters
    module Redis
      module_function

      def install!(app_root:)
        return unless defined?(::RedisClient::Middlewares)
        return unless defined?(::OpenTelemetry::Instrumentation::Redis)

        patch_module = patch_module_for
        patch_module.configure(app_root: app_root)

        return if ::RedisClient::Middlewares.ancestors.include?(patch_module)

        ::RedisClient::Middlewares.prepend(patch_module)
      end

      def patch_module_for
        @patch_module ||= build_patch_module
      end

      def build_patch_module
        mod = Module.new do
          class << self
            attr_accessor :app_root

            def configure(app_root:)
              @app_root = app_root.to_s
            end

            def source_location_for_app
              return unless Thread.respond_to?(:each_caller_location)

              Thread.each_caller_location do |location|
                path = location.absolute_path || location.path
                next unless path&.start_with?(app_root)
                next if path.include?('/gems/')

                return [path.delete_prefix("#{app_root}/"), location.lineno]
              end

              nil
            end
          end

          define_method(:call) do |command, redis_config, &block|
            source = mod.source_location_for_app
            return super(command, redis_config, &block) unless source

            OpenTelemetry::Instrumentation::Redis.with_attributes(
              'code.filepath' => source[0],
              'code.lineno' => source[1]
            ) do
              super(command, redis_config, &block)
            end
          end

          define_method(:call_pipelined) do |commands, redis_config, &block|
            source = mod.source_location_for_app
            return super(commands, redis_config, &block) unless source

            OpenTelemetry::Instrumentation::Redis.with_attributes(
              'code.filepath' => source[0],
              'code.lineno' => source[1]
            ) do
              super(commands, redis_config, &block)
            end
          end
        end
        mod
      end
      private_class_method :build_patch_module
    end
  end
end
