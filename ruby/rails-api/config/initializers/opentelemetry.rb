require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

# Adds service.namespace from request-scoped storage to every span.
# CurrentRequest resets automatically between requests — no cross-request leakage.
class NamespaceSpanProcessor < OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor
  def on_start(span, parent_context)
    namespace = CurrentRequest.service_namespace rescue nil
    span.set_attribute("service.namespace", namespace) if namespace
  end
end

# Reduces trace volume by dropping high-cardinality, low-value spans before export.
#
# Drops by default:
#   - DB transaction boundary spans (BEGIN / COMMIT / ROLLBACK) — high volume, no debug value
#   - HTTP health check paths (/health, /healthz, /ping, /readyz, /livez)
#   - OTLP exporter's own HTTP calls (prevents meta-tracing feedback loop)
#   - Noisy Redis commands (HGET, HSET, HMGET, HMSET, EXPIRE, TTL, EXISTS, PIPELINED)
#
# Configurable via env vars:
#   OTEL_FILTER_PATHS          — comma-separated URL paths to drop (e.g. /admin,/metrics)
#   OTEL_FILTER_HOSTS          — comma-separated hostnames to drop (e.g. internal.svc)
#   OTEL_FILTER_SPAN_NAMES     — comma-separated span name substrings to drop
#   OTEL_FILTER_REDIS_COMMANDS — override Redis commands to drop (e.g. GET,SET,DEL)
#   OTEL_FILTER_SIDEKIQ_QUEUES — drop all spans from these Sidekiq queues (e.g. mailers,low)
#   OTEL_FILTER_SIDEKIQ_JOBS   — drop all spans from these Sidekiq job classes (e.g. HeartbeatJob)
class OtelFilterSpanProcessor
  DB_TRANSACTION_PATTERN = /\A(BEGIN|COMMIT|ROLLBACK)/i

  DEFAULT_DROP_PATHS = %w[
    /health /healthz /ping /readyz /livez /metrics /favicon.ico
  ].freeze

  DEFAULT_REDIS_NOISE_COMMANDS = %w[
    HGET HSET HMGET HMSET HGETALL HDEL
    GET SET SETEX SETNX GETEX
    EXPIRE TTL PEXPIRE PTTL EXISTS DEL
    PIPELINED MULTI EXEC
  ].freeze

  def initialize(delegate_processor)
    @delegate       = delegate_processor
    @drop_paths     = build_drop_paths
    @drop_hosts     = build_drop_hosts
    @drop_names     = build_drop_names
    @redis_commands = build_redis_commands
    @sidekiq_queues = build_sidekiq_queues
    @sidekiq_jobs   = build_sidekiq_jobs
  end

  def on_start(span, parent_context)
    @delegate.on_start(span, parent_context)
  end

  def on_finish(span)
    @delegate.on_finish(span) unless drop?(span)
  end

  def force_flush(timeout: nil)
    @delegate.force_flush(timeout: timeout)
  end

  def shutdown(timeout: nil)
    @delegate.shutdown(timeout: timeout)
  end

  private

  def drop?(span)
    drop_by_span_name?(span.name) ||
      drop_by_http_path?(span.attributes) ||
      drop_by_peer_host?(span.attributes) ||
      drop_redis_noise?(span) ||
      drop_sidekiq_noise?(span)
  end

  def drop_by_span_name?(name)
    return true if name.match?(DB_TRANSACTION_PATTERN)
    @drop_names.any? { |pattern| name.include?(pattern) }
  end

  def drop_by_http_path?(attrs)
    target = attrs['http.target'] || attrs['url.path'] || ''
    return false if target.empty?
    @drop_paths.any? { |p| target == p || target.start_with?("#{p}/") }
  end

  def drop_by_peer_host?(attrs)
    host = attrs['net.peer.name'] || attrs['server.address'] || ''
    return false if host.empty?
    @drop_hosts.any? { |h| host == h || host.end_with?(".#{h}") }
  end

  def drop_redis_noise?(span)
    return false unless span.attributes['db.system'] == 'redis'
    @redis_commands.include?(span.name.upcase)
  end

  def drop_sidekiq_noise?(span)
    return false unless span.attributes['messaging.system'] == 'sidekiq'
    queue = span.attributes['messaging.destination'] || ''
    job   = span.attributes['messaging.sidekiq.job_class'] || ''
    @sidekiq_queues.include?(queue) || @sidekiq_jobs.include?(job)
  end

  def build_drop_paths
    env = ENV.fetch('OTEL_FILTER_PATHS', '').split(',').map(&:strip).reject(&:empty?)
    (DEFAULT_DROP_PATHS + env).uniq
  end

  def build_drop_hosts
    hosts = []
    if (endpoint = ENV['OTEL_EXPORTER_OTLP_ENDPOINT'])
      uri = URI.parse(endpoint) rescue nil
      hosts << uri.host if uri&.host
    end
    env = ENV.fetch('OTEL_FILTER_HOSTS', '').split(',').map(&:strip).reject(&:empty?)
    (hosts + env).uniq
  end

  def build_drop_names
    ENV.fetch('OTEL_FILTER_SPAN_NAMES', '').split(',').map(&:strip).reject(&:empty?)
  end

  def build_redis_commands
    env = ENV.fetch('OTEL_FILTER_REDIS_COMMANDS', '')
    return DEFAULT_REDIS_NOISE_COMMANDS.to_set if env.empty?
    env.split(',').map { |c| c.strip.upcase }.reject(&:empty?).to_set
  end

  def build_sidekiq_queues
    ENV.fetch('OTEL_FILTER_SIDEKIQ_QUEUES', '').split(',').map(&:strip).reject(&:empty?).to_set
  end

  def build_sidekiq_jobs
    ENV.fetch('OTEL_FILTER_SIDEKIQ_JOBS', '').split(',').map(&:strip).reject(&:empty?).to_set
  end
end

otel_exporter      = OpenTelemetry::Exporter::OTLP::Exporter.new
batch_processor    = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(otel_exporter)
filter_processor   = OtelFilterSpanProcessor.new(batch_processor)
namespace_processor = NamespaceSpanProcessor.new(otel_exporter)

OpenTelemetry::SDK.configure do |c|
  c.add_span_processor(namespace_processor)
  c.add_span_processor(filter_processor)

  # Probabilistic sampling via OTEL_SAMPLE_RATE (0.0–1.0).
  # Uses parentbased_traceidratio so downstream services respect the parent's decision.
  if (rate = ENV['OTEL_SAMPLE_RATE']&.to_f) && rate < 1.0
    c.sampler = OpenTelemetry::SDK::Trace::Samplers.parent_based(
      root: OpenTelemetry::SDK::Trace::Samplers.trace_id_ratio_based(rate.clamp(0.0, 1.0))
    )
  end

  c.resource = OpenTelemetry::SDK::Resources::Resource.create({
    OpenTelemetry::SemanticConventions::Resource::SERVICE_NAME => ENV['OTEL_SERVICE_NAME'] || 'ruby-on-rails-api-service',
    OpenTelemetry::SemanticConventions::Resource::SERVICE_VERSION => "0.0.0",
    OpenTelemetry::SemanticConventions::Resource::DEPLOYMENT_ENVIRONMENT => Rails.env.to_s
  })

  c.use_all('OpenTelemetry::Instrumentation::ActionView' => { enabled: false })
end
