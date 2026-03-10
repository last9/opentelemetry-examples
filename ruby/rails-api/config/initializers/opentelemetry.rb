require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

# Optional app-level hook for custom span naming.
# Override in app config:
# Rails.application.config.x.otel_span_name_customizer = lambda do |default_name:, span:, parent_span:, context:|
#   default_name
# end
Rails.application.config.x.otel_span_name_customizer ||= lambda do |default_name:, span:, parent_span:, context:|
  default_name
end

# Custom SpanProcessor that adds service.namespace from request-scoped storage
class NamespaceSpanProcessor < OpenTelemetry::SDK::Trace::SpanProcessor
  def on_start(span, parent_context)
    # Get namespace from request-scoped CurrentAttributes (not baggage)
    # CurrentRequest resets automatically between requests - no leakage
    namespace = CurrentRequest.service_namespace rescue nil
    span.set_attribute("service.namespace", namespace) if namespace
  end
end

# Adds normalized ActiveRecord model and method names from AR instrumentation span names.
class ActiveRecordModelMethodSpanProcessor < OpenTelemetry::SDK::Trace::SpanProcessor
  MODEL_METHOD_REGEX = /\A(?<model>[A-Z]\w*(?:::[A-Z]\w*)*)(?<separator>[#.])(?<method>[a-z_]\w*[!?]?)\z/.freeze
  QUERY_REGEX = /\A(?<model>[A-Z]\w*(?:::[A-Z]\w*)*) query\z/.freeze

  def on_start(span, parent_context)
    return unless span.name

    if (match = MODEL_METHOD_REGEX.match(span.name))
      canonical_method = canonicalize_method(match[:method])
      default_name = "#{match[:model]}##{canonical_method}"
      span.name = resolve_custom_span_name(
        default_name: default_name,
        span: span,
        parent_span: nil,
        context: {
          source: "active_record_method_name_normalization",
          model: match[:model],
          method: canonical_method,
          original_name: span.name
        }
      )
      span.set_attribute("active_record.model", match[:model])
      span.set_attribute("active_record.method", canonical_method)
      span.set_attribute("active_record.method_type", match[:separator] == "#" ? "instance" : "class")
      return
    end

    if (match = QUERY_REGEX.match(span.name))
      span.set_attribute("active_record.model", match[:model])
      span.set_attribute("active_record.method", "query")
      # Normalize query span names from "Model query" to "Model.query"
      default_name = "#{match[:model]}.query"
      span.name = resolve_custom_span_name(
        default_name: default_name,
        span: span,
        parent_span: nil,
        context: { source: "active_record_query_name_normalization", model: match[:model], method: "query" }
      )
    end
  end

  private

  def canonicalize_method(method_name)
    method_name.to_s.sub(/[!?]\z/, "")
  end

  def resolve_custom_span_name(default_name:, span:, parent_span:, context:)
    customizer = Rails.application.config.x.otel_span_name_customizer
    return default_name unless customizer.respond_to?(:call)

    customizer.call(default_name: default_name, span: span, parent_span: parent_span, context: context) || default_name
  rescue StandardError
    default_name
  end
end

# Enrich SQL client span names with ActiveRecord model/method context when available.
class SqlSpanNameEnrichmentProcessor < OpenTelemetry::SDK::Trace::SpanProcessor
  SQL_SYSTEMS = %w[postgresql mysql mariadb sqlite clickhouse].freeze
  MODEL_METHOD_REGEX = /\A(?<model>[A-Z]\w*(?:::[A-Z]\w*)*)(?<separator>[#.])(?<method>[a-z_]\w*[!?]?)\z/.freeze
  QUERY_SPACE_REGEX = /\A(?<model>[A-Z]\w*(?:::[A-Z]\w*)*) query\z/.freeze
  QUERY_DOT_REGEX = /\A(?<model>[A-Z]\w*(?:::[A-Z]\w*)*)\.query\z/.freeze

  def on_start(span, parent_context)
    return unless sql_client_span?(span)

    parent_span = OpenTelemetry::Trace.current_span(parent_context)
    return unless parent_span&.context&.valid?

    model, method_name = active_record_context(parent_span.name)
    return unless model && method_name

    suffix = "(#{model}.#{method_name})"
    default_name = span.name.include?(suffix) ? span.name : "#{span.name} #{suffix}"
    span.name = resolve_custom_span_name(
      default_name: default_name,
      span: span,
      parent_span: parent_span,
      context: {
        source: "sql_span_name_enrichment",
        model: model,
        method: method_name,
        db_system: span.attributes["db.system"]
      }
    )

    existing_attrs = span.attributes
    span.set_attribute("active_record.model", model) unless existing_attrs.key?("active_record.model")
    span.set_attribute("active_record.method", method_name) unless existing_attrs.key?("active_record.method")
  end

  private

  def sql_client_span?(span)
    return false unless span.kind == :client

    system = span.attributes["db.system"]
    SQL_SYSTEMS.include?(system)
  end

  def active_record_context(parent_span_name)
    return [nil, nil] if parent_span_name.nil?

    if (match = MODEL_METHOD_REGEX.match(parent_span_name))
      return [match[:model], match[:method]]
    end
    if (match = QUERY_SPACE_REGEX.match(parent_span_name))
      return [match[:model], "query"]
    end
    if (match = QUERY_DOT_REGEX.match(parent_span_name))
      return [match[:model], "query"]
    end

    [nil, nil]
  end

  def resolve_custom_span_name(default_name:, span:, parent_span:, context:)
    customizer = Rails.application.config.x.otel_span_name_customizer
    return default_name unless customizer.respond_to?(:call)

    customizer.call(default_name: default_name, span: span, parent_span: parent_span, context: context) || default_name
  rescue StandardError
    default_name
  end
end

# Exporter and Processor configuration.
# Supports OTLP (default) and console exporter via `OTEL_TRACES_EXPORTER=console`.
trace_exporter =
  if ENV['OTEL_TRACES_EXPORTER']&.strip == 'console'
    OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
  else
    OpenTelemetry::Exporter::OTLP::Exporter.new
  end
batch_processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(trace_exporter)
namespace_processor = NamespaceSpanProcessor.new
active_record_model_method_processor = ActiveRecordModelMethodSpanProcessor.new
sql_span_name_processor = SqlSpanNameEnrichmentProcessor.new

OpenTelemetry::SDK.configure do |c|
  # Add processors - custom processors enrich spans, batch processor exports
  c.add_span_processor(namespace_processor)
  c.add_span_processor(active_record_model_method_processor)
  c.add_span_processor(sql_span_name_processor)
  c.add_span_processor(batch_processor)

  # Resource configuration
  c.resource = OpenTelemetry::SDK::Resources::Resource.create({
    OpenTelemetry::SemanticConventions::Resource::SERVICE_NAME => 'ruby-on-rails-api-service',
    OpenTelemetry::SemanticConventions::Resource::SERVICE_VERSION => "0.0.0",
    OpenTelemetry::SemanticConventions::Resource::DEPLOYMENT_ENVIRONMENT => Rails.env.to_s
  })

  c.use_all() # enables all instrumentation!
end
