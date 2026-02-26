-- OpenTelemetry tracer for OpenResty
--
-- Implements W3C Trace Context (traceparent) propagation and OTLP/HTTP JSON export.
-- Produces two spans per proxied request:
--   1. A SERVER span for the full request lifecycle
--   2. A CLIENT child span for the upstream proxy_pass call
--
-- Spans are exported asynchronously via ngx.timer.at to avoid blocking.
-- No external Lua libraries required beyond OpenResty builtins (resty.http, cjson).

local _M = {}

local http  = require "resty.http"
local json  = require "cjson.safe"
local bit   = require "bit"

-- Config from environment
local OTLP_ENDPOINT  = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT") or "http://otel-collector:4318"
local SERVICE_NAME   = os.getenv("OTEL_SERVICE_NAME")            or "openresty"
local SERVICE_VER    = os.getenv("OTEL_SERVICE_VERSION")         or "1.0.0"
local ENVIRONMENT    = os.getenv("DEPLOYMENT_ENVIRONMENT")       or "production"

-- Seed PRNG once per worker (Lua 5.1 math.random)
math.randomseed(ngx.now() * 1000 + ngx.worker.id())

-- Generate a cryptographically-weak but sufficient random hex string.
-- OpenResty does not expose /dev/urandom easily in Lua; for production
-- consider using resty.string.to_hex(ngx.var.request_id) for trace IDs.
local function rand_hex(bytes)
    local t = {}
    for i = 1, bytes do
        t[i] = string.format("%02x", math.random(0, 255))
    end
    return table.concat(t)
end

-- Parse W3C traceparent: "00-<trace_id>-<parent_id>-<flags>"
local function parse_traceparent(header)
    if not header then return nil, nil, nil end
    local v, tid, pid, flags = header:match("^(%x%x)-(%x+)-(%x+)-(%x%x)$")
    if v == "00" and tid and #tid == 32 and pid and #pid == 16 then
        return tid, pid, flags
    end
    return nil, nil, nil
end

-- Format a traceparent header value
local function make_traceparent(trace_id, span_id, sampled)
    return string.format("00-%s-%s-%s", trace_id, span_id, sampled and "01" or "00")
end

-- Build an OTLP span table (not yet JSON-encoded)
local function build_span(trace_id, span_id, parent_span_id, name, kind,
                          start_ns, end_ns, attrs, status_code, events)
    local span = {
        traceId            = trace_id,
        spanId             = span_id,
        name               = name,
        kind               = kind,
        startTimeUnixNano  = tostring(math.floor(start_ns)),
        endTimeUnixNano    = tostring(math.floor(end_ns)),
        attributes         = attrs or {},
        status             = { code = status_code or 0 },
    }
    if parent_span_id then
        span.parentSpanId = parent_span_id
    end
    if events and #events > 0 then
        span.events = events
    end
    return span
end

-- Wrap a list of spans in the OTLP resourceSpans envelope
local function build_payload(spans)
    return {
        resourceSpans = {
            {
                resource = {
                    attributes = {
                        { key = "service.name",            value = { stringValue = SERVICE_NAME } },
                        { key = "service.version",         value = { stringValue = SERVICE_VER } },
                        { key = "deployment.environment",  value = { stringValue = ENVIRONMENT } },
                    }
                },
                scopeSpans = {
                    {
                        scope = { name = "openresty-otel", version = "0.1.0" },
                        spans = spans,
                    }
                }
            }
        }
    }
end

-- Export a payload to the collector asynchronously
local function export_spans(payload)
    local body, err = json.encode(payload)
    if not body then
        ngx.log(ngx.WARN, "[otel] json encode failed: ", err)
        return
    end

    local ok, timer_err = ngx.timer.at(0, function(premature)
        if premature then return end
        local httpc = http.new()
        httpc:set_timeout(2000)
        local res, req_err = httpc:request_uri(OTLP_ENDPOINT .. "/v1/traces", {
            method  = "POST",
            headers = { ["Content-Type"] = "application/json" },
            body    = body,
        })
        if req_err then
            ngx.log(ngx.WARN, "[otel] export failed: ", req_err)
        elseif res and res.status >= 400 then
            ngx.log(ngx.WARN, "[otel] export HTTP ", res.status, ": ", res.body)
        end
    end)

    if not ok then
        ngx.log(ngx.WARN, "[otel] timer create failed: ", timer_err)
    end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Called in access_by_lua_block.
-- Extracts or generates trace context, stores it in ngx.ctx,
-- and injects traceparent into the upstream request.
function _M.start_span()
    local ctx = ngx.ctx

    local incoming = ngx.req.get_headers()["traceparent"]
    local trace_id, parent_span_id = parse_traceparent(incoming)

    trace_id       = trace_id or rand_hex(16)
    local span_id  = rand_hex(8)

    -- Child CLIENT span id used for the upstream proxy_pass call
    local upstream_span_id = rand_hex(8)

    ctx.otel = {
        trace_id           = trace_id,
        span_id            = span_id,
        parent_span_id     = parent_span_id,
        upstream_span_id   = upstream_span_id,
        start_ns           = ngx.now() * 1e9,
        method             = ngx.req.get_method(),
        uri                = ngx.var.request_uri,
        host               = ngx.var.host or "",
        remote_addr        = ngx.var.remote_addr or "",
        user_agent         = ngx.req.get_headers()["user-agent"] or "",
        content_length_req = tonumber(ngx.req.get_headers()["content-length"]) or 0,
    }

    -- Propagate W3C trace context to upstream
    ngx.req.set_header("traceparent",
        make_traceparent(trace_id, upstream_span_id, true))
end

-- Called in log_by_lua_block.
-- Collects response metadata, builds parent SERVER span and optional
-- CLIENT child span for the upstream call, then exports both.
function _M.finish_span()
    local ctx = ngx.ctx
    local o   = ctx.otel
    if not o then return end

    local end_ns    = ngx.now() * 1e9
    local status    = ngx.status or 0
    local is_error  = status >= 500

    -- Span status: 0=UNSET, 1=OK, 2=ERROR
    local otel_status = is_error and 2 or 0

    -- ── SERVER span attributes ────────────────────────────────────────────
    local server_attrs = {
        { key = "http.method",              value = { stringValue  = o.method } },
        { key = "http.target",              value = { stringValue  = o.uri } },
        { key = "http.host",                value = { stringValue  = o.host } },
        { key = "http.scheme",              value = { stringValue  = "http" } },
        { key = "http.status_code",         value = { intValue     = status } },
        { key = "http.user_agent",          value = { stringValue  = o.user_agent } },
        { key = "net.peer.ip",              value = { stringValue  = o.remote_addr } },
        { key = "http.request_content_length",
                                            value = { intValue     = o.content_length_req } },
    }

    -- Attach response size if nginx variable is available
    local resp_bytes = tonumber(ngx.var.bytes_sent)
    if resp_bytes then
        server_attrs[#server_attrs + 1] = {
            key = "http.response_content_length", value = { intValue = resp_bytes }
        }
    end

    -- ── Error events ─────────────────────────────────────────────────────
    local events = {}
    if is_error then
        events[#events + 1] = {
            name              = "exception",
            timeUnixNano      = tostring(math.floor(end_ns)),
            attributes        = {
                { key = "exception.message",
                  value = { stringValue = string.format("HTTP %d from upstream", status) } },
            }
        }
    end

    -- ── SERVER span ───────────────────────────────────────────────────────
    local server_span = build_span(
        o.trace_id,
        o.span_id,
        o.parent_span_id,
        string.format("%s %s", o.method, o.uri),
        2,  -- SPAN_KIND_SERVER
        o.start_ns,
        end_ns,
        server_attrs,
        otel_status,
        events
    )

    local spans = { server_span }

    -- ── CLIENT child span for upstream call ───────────────────────────────
    local upstream_rt = tonumber(ngx.var.upstream_response_time)
    if upstream_rt then
        local upstream_addr   = ngx.var.upstream_addr   or ""
        local upstream_status = tonumber(ngx.var.upstream_status) or 0

        -- Approximate upstream start time: end - response_time
        local upstream_end_ns   = end_ns
        local upstream_start_ns = end_ns - upstream_rt * 1e9

        local upstream_attrs = {
            { key = "http.method",         value = { stringValue = o.method } },
            { key = "http.url",            value = { stringValue = o.uri } },
            { key = "http.status_code",    value = { intValue    = upstream_status } },
            { key = "net.peer.name",       value = { stringValue = upstream_addr } },
            { key = "span.kind",           value = { stringValue = "client" } },
        }

        local client_span = build_span(
            o.trace_id,
            o.upstream_span_id,
            o.span_id,   -- parent = server span
            string.format("%s %s (upstream)", o.method, o.uri),
            3,  -- SPAN_KIND_CLIENT
            upstream_start_ns,
            upstream_end_ns,
            upstream_attrs,
            upstream_status >= 500 and 2 or 0
        )

        spans[#spans + 1] = client_span
    end

    export_spans(build_payload(spans))
end

return _M
