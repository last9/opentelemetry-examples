-- Prometheus metrics initialization for OpenResty.
-- Uses lua-resty-prometheus (knyar/nginx-lua-prometheus) which is installed
-- via opm in the Dockerfile.
--
-- Counters and histograms are stored in a shared dict (prometheus_metrics)
-- so they accumulate correctly across all nginx worker processes.

local _M = {}

-- Prometheus instance, initialized once per worker in init_worker_by_lua_block
local prom

local metric_requests
local metric_latency
local metric_upstream_latency
local metric_connections

function _M.init()
    local prometheus = require "prometheus"
    prom = prometheus.init("prometheus_metrics")

    metric_requests = prom:counter(
        "openresty_http_requests_total",
        "Total number of HTTP requests processed",
        { "method", "status" }
    )

    metric_latency = prom:histogram(
        "openresty_http_request_duration_seconds",
        "Total HTTP request duration in seconds (gateway to client)",
        { "method", "status" },
        { 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5 }
    )

    metric_upstream_latency = prom:histogram(
        "openresty_upstream_response_duration_seconds",
        "Upstream response time in seconds",
        { "upstream" },
        { 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5 }
    )

    metric_connections = prom:gauge(
        "openresty_connections_active",
        "Number of active client connections"
    )

    _M.prom = prom
end

-- Called in log_by_lua_block after each request
function _M.record()
    if not metric_requests then return end

    local method = ngx.req.get_method()
    local status = tostring(ngx.status)
    local latency = ngx.now() - ngx.req.start_time()

    metric_requests:inc(1, { method, status })
    metric_latency:observe(latency, { method, status })

    local upstream_rt = tonumber(ngx.var.upstream_response_time)
    if upstream_rt then
        local upstream = ngx.var.upstream_addr or "unknown"
        metric_upstream_latency:observe(upstream_rt, { upstream })
    end
end

-- Expose the prometheus instance for the /metrics endpoint
function _M.collect()
    if not prom then
        ngx.status = 503
        ngx.say("metrics not initialized")
        return
    end

    -- Update active connections gauge at scrape time
    if metric_connections then
        local connections = tonumber(ngx.var.connections_active) or 0
        metric_connections:set(connections)
    end

    prom:collect()
end

return _M
