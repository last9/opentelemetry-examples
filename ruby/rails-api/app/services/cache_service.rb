# Service for Redis cache operations - creates child spans in traces
class CacheService
  class << self
    def redis
      @redis ||= Redis.new(
        url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
        timeout: 1,
        reconnect_attempts: 1
      )
    rescue Redis::CannotConnectError
      nil
    end

    def get(key)
      tracer.in_span("cache.get", attributes: { "cache.key" => key }) do |span|
        begin
          value = redis&.get(key)
          span.set_attribute("cache.hit", !value.nil?)
          value
        rescue Redis::BaseError => e
          span.set_attribute("cache.error", e.message)
          span.status = OpenTelemetry::Trace::Status.error(e.message)
          nil
        end
      end
    end

    def set(key, value, ex: 300)
      tracer.in_span("cache.set", attributes: { "cache.key" => key, "cache.ttl" => ex }) do |span|
        begin
          redis&.set(key, value, ex: ex)
          span.set_attribute("cache.success", true)
          true
        rescue Redis::BaseError => e
          span.set_attribute("cache.error", e.message)
          span.status = OpenTelemetry::Trace::Status.error(e.message)
          false
        end
      end
    end

    def delete(key)
      tracer.in_span("cache.delete", attributes: { "cache.key" => key }) do |span|
        begin
          result = redis&.del(key)
          span.set_attribute("cache.keys_deleted", result || 0)
          result
        rescue Redis::BaseError => e
          span.set_attribute("cache.error", e.message)
          nil
        end
      end
    end

    def increment(key, by: 1)
      tracer.in_span("cache.increment", attributes: { "cache.key" => key, "cache.increment_by" => by }) do |span|
        begin
          result = redis&.incrby(key, by)
          span.set_attribute("cache.new_value", result) if result
          result
        rescue Redis::BaseError => e
          span.set_attribute("cache.error", e.message)
          nil
        end
      end
    end

    private

    def tracer
      OpenTelemetry.tracer_provider.tracer('cache-service')
    end
  end
end
