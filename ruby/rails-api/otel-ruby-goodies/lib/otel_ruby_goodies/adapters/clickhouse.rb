# frozen_string_literal: true

module OTelRubyGoodies
  module Adapters
    module Clickhouse
      module_function

      CANDIDATE_METHODS = %i[query select insert execute command].freeze

      def install!(app_root:, threshold_ms:)
        begin
          require 'click_house'
        rescue LoadError
          # ClickHouse client gem is optional for consumers.
        end

        target_clients.each do |klass|
          methods = CANDIDATE_METHODS.select { |method_name| klass.instance_methods.include?(method_name) }
          next if methods.empty?

          patch_module = patch_module_for(klass, methods)
          patch_module.configure(app_root: app_root, threshold_ms: threshold_ms)
          next if klass.ancestors.include?(patch_module)

          klass.prepend(patch_module)
        end
      end

      def target_clients
        clients = []

        clients << ::ClickHouse::Client if defined?(::ClickHouse::Client)
        clients << ::ClickHouse::Connection if defined?(::ClickHouse::Connection)
        clients << ::Clickhouse::Client if defined?(::Clickhouse::Client)

        clients.compact.uniq
      end

      def patch_module_for(klass, methods)
        @patch_modules ||= {}
        key = [klass.name, methods.sort].join(':')
        @patch_modules[key] ||= build_patch_module(methods)
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
            define_method(method_name) do |*args, &block|
              if Thread.current[:otel_goodies_clickhouse_instrumenting]
                return super(*args, &block)
              end

              source = mod.source_location_for_app
              started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              operation = method_name.to_s.upcase
              statement = args.first.is_a?(String) ? args.first : nil

              tracer = OpenTelemetry.tracer_provider.tracer('otel-ruby-goodies-clickhouse')
              Thread.current[:otel_goodies_clickhouse_instrumenting] = true

              tracer.in_span("#{operation} clickhouse", kind: :client) do |span|
                span.set_attribute('db.system', 'clickhouse')
                span.set_attribute('db.operation', operation)
                span.set_attribute('db.statement', statement) if statement

                result = super(*args, &block)
                duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0

                if source && duration_ms >= mod.threshold_ms
                  span.set_attribute('code.filepath', source[0])
                  span.set_attribute('code.lineno', source[1])
                  span.set_attribute('db.query.duration_ms', duration_ms.round(1))
                  span.set_attribute('db.query.slow_threshold_ms', mod.threshold_ms)
                end

                result
              end
            ensure
              Thread.current[:otel_goodies_clickhouse_instrumenting] = false
            end
          end
        end

        mod
      end
      private_class_method :build_patch_module
    end
  end
end
