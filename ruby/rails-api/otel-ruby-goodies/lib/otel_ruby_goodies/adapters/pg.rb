# frozen_string_literal: true

module OTelRubyGoodies
  module Adapters
    module PG
      module_function

      def install!(app_root:, threshold_ms:)
        return unless defined?(::PG::Connection)

        methods = exec_methods
        return if methods.empty?

        patch_module = patch_module_for(methods)
        patch_module.configure(app_root: app_root, threshold_ms: threshold_ms)

        return if ::PG::Connection.ancestors.include?(patch_module)

        ::PG::Connection.prepend(patch_module)
      end

      def exec_methods
        return [] unless defined?(::PG::Constants::EXEC_ISH_METHODS)
        return [] unless defined?(::PG::Constants::EXEC_PREPARED_ISH_METHODS)

        (::PG::Constants::EXEC_ISH_METHODS + ::PG::Constants::EXEC_PREPARED_ISH_METHODS).uniq
      end

      def patch_module_for(methods)
        @patch_module ||= build_patch_module(methods)
      end

      def build_patch_module(methods)
        mod = Module.new do
          class << self
            attr_accessor :app_root, :threshold_ms

            def configure(app_root:, threshold_ms:)
              @app_root = app_root.to_s
              @threshold_ms = threshold_ms.to_f
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

          methods.each do |method_name|
            define_method(method_name) do |*args, &user_block|
              source = mod.source_location_for_app
              started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

              super(*args) do |result|
                duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0

                if source && duration_ms >= mod.threshold_ms
                  span = OpenTelemetry::Trace.current_span
                  span.set_attribute('code.filepath', source[0])
                  span.set_attribute('code.lineno', source[1])
                  span.set_attribute('db.query.duration_ms', duration_ms.round(1))
                  span.set_attribute('db.query.slow_threshold_ms', mod.threshold_ms)
                end

                user_block ? user_block.call(result) : result
              end
            end
          end
        end
        mod
      end
      private_class_method :build_patch_module
    end
  end
end
