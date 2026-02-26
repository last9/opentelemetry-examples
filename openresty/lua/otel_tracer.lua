-- OpenTelemetry tracer for OpenResty
-- Runtime: LuaJIT (Lua 5.1). Do NOT use Lua 5.2+ syntax:
--   NO: &, |, ~, >>, <<  (bitwise operators — use bit.band / bit.bor / etc.)
--   NO: //               (integer division operator)
--   NO: goto, <const>, <close>, table.pack, table.move, utf8.*
--
-- Implements W3C Trace Context (traceparent + tracestate) propagation
-- and OTLP/HTTP JSON export.
--
-- Produces per proxied request:
--   1. A SERVER span for the full request lifecycle
--   2. One CLIENT child span per upstream attempt (handles retries/failover)
--
-- Sampling via OTEL_TRACES_SAMPLER:
--   always_on | always_off | traceid_ratio
--   | parentbased_always_on (default) | parentbased_traceid_ratio
--
-- Spans are exported asynchronously via ngx.timer.at to avoid blocking.
-- No external Lua libraries required beyond OpenResty builtins (resty.http, cjson).

local _M = {}

local http = require "resty.http"
local json = require "cjson.safe"
local bit  = require "bit"

-- ── Config from environment ───────────────────────────────────────────────────

local OTLP_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT") or "http://otel-collector:4318"
local SERVICE_NAME  = os.getenv("OTEL_SERVICE_NAME")            or "openresty"
local SERVICE_VER   = os.getenv("OTEL_SERVICE_VERSION")         or "1.0.0"
local ENVIRONMENT   = os.getenv("DEPLOYMENT_ENVIRONMENT")       or "production"
local SAMPLER       = os.getenv("OTEL_TRACES_SAMPLER")          or "parentbased_always_on"
local SAMPLER_ARG   = tonumber(os.getenv("OTEL_TRACES_SAMPLER_ARG"))         or 1.0
local ATTR_LIMIT    = tonumber(os.getenv("OTEL_ATTRIBUTE_VALUE_LENGTH_LIMIT")) or 256

-- ── Helpers ───────────────────────────────────────────────────────────────────

-- Truncate string attributes to prevent OOM on large headers/URIs.
local function trunc(s)
    if type(s) ~= "string" or #s <= ATTR_LIMIT then return s end
    return s:sub(1, ATTR_LIMIT)
end

-- Convert ngx.now() float (seconds) to a nanosecond decimal string for OTLP
-- uint64 fields. Lua doubles represent integers exactly up to 2^53; a Unix
-- timestamp in nanoseconds (~1.77e18) exceeds that, so we split to avoid
-- scientific notation from tostring().
local function ns_string(t)
    local secs    = math.floor(t)
    local frac_ns = math.floor((t - secs) * 1e9)
    return string.format("%d%09d", secs, frac_ns)
end

-- Seed PRNG once per worker (Lua 5.1 math.random)
math.randomseed(ngx.now() * 1000 + ngx.worker.id())

local function rand_hex(bytes)
    local t = {}
    for i = 1, bytes do
        t[i] = string.format("%02x", math.random(0, 255))
    end
    return table.concat(t)
end

-- Split a URL into path and query string components.
local function split_uri(uri)
    local path, query = uri:match("^([^?]*)%??(.*)")
    return path or uri, query or ""
end

-- Split nginx's comma-separated upstream variable values (e.g. $upstream_addr).
-- Returns an array of trimmed strings; empty/dash input → empty array.
local function split_csv(s)
    local parts = {}
    if not s or s == "" or s == "-" then return parts end
    for part in s:gmatch("[^,]+") do
        parts[#parts + 1] = part:match("^%s*(.-)%s*$")
    end
    return parts
end

-- ── Sampling ──────────────────────────────────────────────────────────────────
--
-- parent_sampled: bool (from incoming traceparent flags) or nil (no parent).
-- Returns true if this trace should produce spans.

local function should_sample(trace_id, parent_sampled)
    if SAMPLER == "always_off" then return false end
    if SAMPLER == "always_on"  then return true  end

    -- Probabilistic: map first 32-bit word of trace_id → [0,1) and compare to ratio.
    -- Using 32 bits is a standard approximation (full 128-bit is overkill in Lua).
    local function ratio_sample()
        local hi = tonumber(trace_id:sub(1, 8), 16) or 0
        return (hi / 0xffffffff) < SAMPLER_ARG
    end

    if SAMPLER == "traceid_ratio" then
        return ratio_sample()
    end

    -- parentbased_always_on (default): honour parent decision; new roots always sample.
    if SAMPLER == "parentbased_always_on" then
        if parent_sampled ~= nil then return parent_sampled end
        return true
    end

    -- parentbased_traceid_ratio: honour parent decision; new roots use ratio.
    if SAMPLER == "parentbased_traceid_ratio" then
        if parent_sampled ~= nil then return parent_sampled end
        return ratio_sample()
    end

    -- parentbased_always_off: honour parent decision; new roots never sample.
    if SAMPLER == "parentbased_always_off" then
        if parent_sampled ~= nil then return parent_sampled end
        return false
    end

    return true  -- safe default
end

-- ── W3C Trace Context ─────────────────────────────────────────────────────────

-- Parse W3C traceparent header: "00-<trace_id>-<parent_id>-<flags>"
-- Returns: trace_id (hex32), parent_span_id (hex16), sampled (bool) or nils.
local function parse_traceparent(header)
    if not header then return nil, nil, nil end
    local v, tid, pid, flags = header:match("^(%x%x)-(%x+)-(%x+)-(%x%x)$")
    if v == "00" and tid and #tid == 32 and pid and #pid == 16 then
        return tid, pid, bit.band(tonumber(flags, 16) or 0, 0x01) == 1
    end
    return nil, nil, nil
end

local function make_traceparent(trace_id, span_id, sampled)
    return string.format("00-%s-%s-%s", trace_id, span_id, sampled and "01" or "00")
end

-- ── OTLP builders ─────────────────────────────────────────────────────────────

local function build_span(trace_id, span_id, parent_span_id, name, kind,
                          start_s, end_s, attrs, status_code, events, tracestate)
    local span = {
        traceId           = trace_id,
        spanId            = span_id,
        name              = name,
        kind              = kind,
        startTimeUnixNano = ns_string(start_s),
        endTimeUnixNano   = ns_string(end_s),
        attributes        = attrs or {},
        status            = { code = status_code or 0 },
    }
    if parent_span_id then span.parentSpanId = parent_span_id end
    if tracestate and tracestate ~= "" then span.traceState = tracestate end
    if events and #events > 0 then span.events = events end
    return span
end

local function build_payload(spans)
    return {
        resourceSpans = {
            {
                resource = {
                    attributes = {
                        { key = "service.name",           value = { stringValue = SERVICE_NAME } },
                        { key = "service.version",        value = { stringValue = SERVICE_VER } },
                        { key = "deployment.environment", value = { stringValue = ENVIRONMENT } },
                    }
                },
                scopeSpans = {
                    {
                        scope = { name = "openresty-otel", version = "0.2.0" },
                        spans = spans,
                    }
                }
            }
        }
    }
end

-- ── Export ────────────────────────────────────────────────────────────────────

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

-- ── Public API ────────────────────────────────────────────────────────────────

-- Called in access_by_lua_block.
-- Extracts or generates trace context, runs sampler, stores state in ngx.ctx,
-- and injects traceparent + tracestate into the upstream request.
function _M.start_span()
    local ctx     = ngx.ctx
    local headers = ngx.req.get_headers()

    local incoming   = headers["traceparent"]
    local tracestate = headers["tracestate"] or ""

    local trace_id, parent_span_id, parent_sampled = parse_traceparent(incoming)
    trace_id = trace_id or rand_hex(16)

    local sampled          = should_sample(trace_id, parent_sampled)
    local span_id          = rand_hex(8)
    local upstream_span_id = rand_hex(8)

    ctx.otel = {
        trace_id           = trace_id,
        span_id            = span_id,
        parent_span_id     = parent_span_id,
        upstream_span_id   = upstream_span_id,  -- reused for attempt #1
        tracestate         = tracestate,
        sampled            = sampled,
        start_t            = ngx.now(),
        method             = ngx.req.get_method(),
        uri                = ngx.var.request_uri,
        host               = ngx.var.host or "",
        scheme             = ngx.var.scheme or "http",
        server_port        = tonumber(ngx.var.server_port),
        proto              = ngx.var.server_protocol or "",
        remote_addr        = ngx.var.remote_addr or "",
        user_agent         = headers["user-agent"] or "",
        req_length         = tonumber(ngx.var.request_length) or 0,
    }

    -- Always propagate context upstream, even when unsampled, so downstream
    -- services can make their own sampling decisions with a consistent trace_id.
    ngx.req.set_header("traceparent",
        make_traceparent(trace_id, upstream_span_id, sampled))
    if tracestate ~= "" then
        ngx.req.set_header("tracestate", tracestate)
    end
end

-- Called in log_by_lua_block.
-- Builds the SERVER span and one CLIENT child span per upstream attempt,
-- then exports the batch asynchronously.
function _M.finish_span()
    local ctx = ngx.ctx
    local o   = ctx.otel
    if not o then return end

    -- Skip span construction for unsampled traces.
    if not o.sampled then return end

    local end_t    = ngx.now()
    local status   = ngx.status or 0
    local is_error = status >= 500
    local is_4xx   = status >= 400 and status < 500

    -- Span status: 0=UNSET, 2=ERROR
    -- Mark 5xx as ERROR; 4xx are client errors (UNSET per OTel server semconv)
    local otel_status = is_error and 2 or 0

    -- Classify error type for error.type attribute and exception events.
    -- OTel semconv: error.type on SERVER span = HTTP status code string for 5xx.
    local function classify_error(st)
        if st == 504 then return "GatewayTimeout"
        elseif st == 502 then return "BadGateway"
        elseif st == 503 then return "ServiceUnavailable"
        elseif st >= 500 then return "InternalServerError"
        elseif st >= 400 then return "ClientError"
        else return nil
        end
    end

    local error_type = classify_error(status)

    -- Decompose URI into path + query for semantic conventions.
    local url_path, url_query = split_uri(o.uri)

    -- Extract protocol version: "HTTP/1.1" → "1.1"
    local proto_ver = o.proto:match("HTTP/(.+)") or ""

    -- ── SERVER span (OTel HTTP semconv v1.23+) ────────────────────────────
    local server_attrs = {
        { key = "http.request.method",       value = { stringValue = o.method } },
        { key = "url.path",                  value = { stringValue = trunc(url_path) } },
        { key = "url.scheme",                value = { stringValue = o.scheme } },
        { key = "server.address",            value = { stringValue = o.host } },
        { key = "http.response.status_code", value = { intValue    = status } },
        { key = "user_agent.original",       value = { stringValue = trunc(o.user_agent) } },
        { key = "client.address",            value = { stringValue = o.remote_addr } },
        { key = "http.request.body.size",    value = { intValue    = o.req_length } },
        { key = "network.protocol.version",  value = { stringValue = proto_ver } },
    }

    if url_query ~= "" then
        server_attrs[#server_attrs + 1] = {
            key = "url.query", value = { stringValue = trunc(url_query) }
        }
    end
    if o.server_port then
        server_attrs[#server_attrs + 1] = {
            key = "server.port", value = { intValue = o.server_port }
        }
    end

    local resp_bytes = tonumber(ngx.var.bytes_sent)
    if resp_bytes then
        server_attrs[#server_attrs + 1] = {
            key = "http.response.body.size", value = { intValue = resp_bytes }
        }
    end

    if error_type then
        server_attrs[#server_attrs + 1] = {
            key = "error.type", value = { stringValue = error_type }
        }
    end

    -- ── Exception events ──────────────────────────────────────────────────
    -- Emit an exception event for any HTTP error (4xx or 5xx).
    -- 5xx → ERROR span status; 4xx → UNSET (client fault per OTel server semconv).
    local events = {}
    if is_error or is_4xx then
        local exc_msg
        if status == 504 then
            exc_msg = "upstream timed out"
        elseif status == 502 then
            exc_msg = "bad gateway: upstream returned an invalid response"
        elseif status == 503 then
            exc_msg = "service unavailable: upstream not reachable"
        elseif is_error then
            exc_msg = string.format("upstream error: HTTP %d", status)
        else
            exc_msg = string.format("client error: HTTP %d", status)
        end

        events[1] = {
            name         = "exception",
            timeUnixNano = ns_string(end_t),
            attributes   = {
                { key = "exception.type",
                  value = { stringValue = error_type or "HTTPError" } },
                { key = "exception.message",
                  value = { stringValue = exc_msg } },
                { key = "http.response.status_code",
                  value = { intValue = status } },
            }
        }
    end

    local server_span = build_span(
        o.trace_id, o.span_id, o.parent_span_id,
        string.format("%s %s", o.method, url_path),
        2,  -- SPAN_KIND_SERVER
        o.start_t, end_t,
        server_attrs, otel_status, events, o.tracestate
    )

    local spans = { server_span }

    -- ── CLIENT child spans: one per upstream attempt ──────────────────────
    --
    -- When nginx retries a failing upstream, it appends to these variables:
    --   $upstream_addr:          "10.0.0.1:80, 10.0.0.2:80"
    --   $upstream_response_time: "0.023, 0.101"
    --   $upstream_status:        "502, 200"
    --   $upstream_cache_status:  "MISS" (single value — applies to final response)
    --
    -- We reconstruct per-attempt timings by working backwards from end_t.
    local addrs        = split_csv(ngx.var.upstream_addr)
    local times        = split_csv(ngx.var.upstream_response_time)
    local statuses     = split_csv(ngx.var.upstream_status)
    local connect_times = split_csv(ngx.var.upstream_connect_time)
    local cache_st     = ngx.var.upstream_cache_status or ""

    local retry_count = math.max(0, #addrs - 1)

    local attempt_end = end_t
    for i = #addrs, 1, -1 do
        local addr    = addrs[i]
        local rt      = tonumber(times[i]) or 0
        local st      = tonumber(statuses[i]) or 0
        local att_start = attempt_end - rt

        -- Attempt #1 reuses upstream_span_id so it matches the traceparent
        -- header we injected into the proxied request.
        local sid = (i == 1) and o.upstream_span_id or rand_hex(8)

        local ct = tonumber(connect_times[i])

        -- Split "host:port" or "unix:..." upstream address
        local upstream_host = addr:match("^([^:]+):%d+$") or addr
        local upstream_port = tonumber(addr:match(":(%d+)$"))

        local upstream_attrs = {
            { key = "http.request.method",       value = { stringValue = o.method } },
            { key = "url.full",                  value = { stringValue = trunc(o.scheme .. "://" .. addr .. o.uri) } },
            { key = "http.response.status_code", value = { intValue    = st } },
            { key = "server.address",            value = { stringValue = upstream_host } },
        }
        if upstream_port then
            upstream_attrs[#upstream_attrs + 1] = {
                key = "server.port", value = { intValue = upstream_port }
            }
        end

        -- upstream.connect_time_ms: milliseconds to establish the TCP connection to upstream.
        -- No stable OTel semconv key exists yet; using custom namespace per OTel guidance.
        if ct then
            upstream_attrs[#upstream_attrs + 1] = {
                key = "upstream.connect_time_ms",
                value = { intValue = math.floor(ct * 1000) }
            }
        end

        if retry_count > 0 then
            upstream_attrs[#upstream_attrs + 1] = {
                key = "http.request.resend_count", value = { intValue = retry_count }
            }
        end

        -- $upstream_cache_status reflects the final cache decision (HIT/MISS/BYPASS/EXPIRED).
        if cache_st ~= "" then
            upstream_attrs[#upstream_attrs + 1] = {
                key = "http.cache_status", value = { stringValue = cache_st }
            }
        end

        -- Detect connection timeout vs response timeout
        local upstream_error_type
        if st == 504 then
            upstream_error_type = (ct == nil or ct < 0) and "ConnectTimeout" or "ResponseTimeout"
        elseif st == 502 then
            upstream_error_type = "BadGateway"
        elseif st == 503 then
            upstream_error_type = "ServiceUnavailable"
        elseif st >= 500 then
            upstream_error_type = "UpstreamError"
        end

        if upstream_error_type then
            upstream_attrs[#upstream_attrs + 1] = {
                key = "error.type", value = { stringValue = upstream_error_type }
            }
        end

        local span_name = (#addrs > 1)
            and string.format("%s %s (upstream %d/%d)", o.method, url_path, i, #addrs)
            or  string.format("%s %s (upstream)", o.method, url_path)

        spans[#spans + 1] = build_span(
            o.trace_id, sid, o.span_id,
            span_name,
            3,  -- SPAN_KIND_CLIENT
            att_start, attempt_end,
            upstream_attrs, st >= 500 and 2 or 0,
            nil, o.tracestate
        )

        attempt_end = att_start
    end

    export_spans(build_payload(spans))
end

return _M
