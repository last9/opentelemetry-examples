"""Chalice middleware that emits a SERVER span per route invocation following
OTel HTTP + FaaS semantic conventions (matches AwsLambdaInstrumentor /
RequestsInstrumentor output shape).

This compensates for not using AwsLambdaInstrumentor (incompatible with Chalice).
Without this middleware, outbound HTTP/SDK calls from the handler become
disconnected root spans instead of children of a server span.
"""
from __future__ import annotations

import os
from typing import Any, Callable

from opentelemetry import context as otel_context
from opentelemetry import trace
from opentelemetry.propagate import extract
from opentelemetry.trace import SpanKind, Status, StatusCode


_tracer = trace.get_tracer("chalicelib.server_span")


def _resource_path(event: Any) -> str:
    ctx = getattr(event, "context", {}) or {}
    return ctx.get("resourcePath") or ctx.get("path") or "/"


def _http_method(event: Any) -> str:
    ctx = getattr(event, "context", {}) or {}
    return ctx.get("httpMethod", "GET")


def _request_headers(event: Any) -> dict:
    raw = (getattr(event, "context", {}) or {}).get("identity", {}) or {}
    # API Gateway proxy event puts headers in event.headers if Chalice exposes them;
    # fall back to context.identity for sourceIp + userAgent.
    return raw


def _carrier_from_event(event: Any) -> dict:
    """Extract W3C traceparent / baggage from API Gateway proxy event headers."""
    hdrs = {}
    # Chalice's event object may expose .to_dict() or .raw_request.headers
    raw = getattr(event, "raw_request", None)
    if raw is not None and hasattr(raw, "headers"):
        hdrs = dict(raw.headers or {})
    else:
        # Fall back to direct attribute lookup
        possible = getattr(event, "headers", None) or {}
        if isinstance(possible, dict):
            hdrs = possible
    # OTel propagator expects lowercased keys
    return {k.lower(): v for k, v in hdrs.items()}


def server_span_middleware(event: Any, get_response: Callable) -> Any:
    """Chalice @app.middleware('all') target.

    Creates a SERVER span around each route invocation with HTTP + FaaS attrs.
    Extracts traceparent from incoming request headers so the trace can join an
    upstream caller's trace tree.
    """
    method = _http_method(event)
    route = _resource_path(event)
    identity = _request_headers(event)

    # Join upstream trace context if traceparent header present
    parent_ctx = extract(_carrier_from_event(event))

    span_name = f"{method} {route}"
    token = otel_context.attach(parent_ctx)
    try:
        with _tracer.start_as_current_span(span_name, kind=SpanKind.SERVER) as span:
            # HTTP semconv (stable form preferred; legacy keys kept for back-compat
            # with Last9 UI and older dashboards)
            span.set_attribute("http.request.method", method)
            span.set_attribute("http.method", method)  # legacy
            span.set_attribute("http.route", route)
            span.set_attribute("url.path", route)
            span.set_attribute("url.scheme", "https")

            user_agent = identity.get("userAgent") or identity.get("user-agent")
            if user_agent:
                span.set_attribute("user_agent.original", user_agent)
                span.set_attribute("http.user_agent", user_agent)  # legacy

            client_ip = identity.get("sourceIp")
            if client_ip:
                span.set_attribute("client.address", client_ip)
                span.set_attribute("net.peer.ip", client_ip)  # legacy

            # FaaS semconv
            faas_invocation_id = os.environ.get("_X_AMZN_TRACE_ID")
            if faas_invocation_id:
                span.set_attribute("faas.invocation_id", faas_invocation_id)
            span.set_attribute("faas.trigger", "http")
            span.set_attribute("cloud.provider", "aws")
            region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")
            if region:
                span.set_attribute("cloud.region", region)
            fn_name = os.environ.get("AWS_LAMBDA_FUNCTION_NAME")
            if fn_name:
                span.set_attribute("faas.name", fn_name)
            fn_version = os.environ.get("AWS_LAMBDA_FUNCTION_VERSION")
            if fn_version:
                span.set_attribute("faas.version", fn_version)

            try:
                response = get_response(event)
            except Exception as exc:
                span.record_exception(exc)
                span.set_status(Status(StatusCode.ERROR, str(exc)))
                raise

            status_code = getattr(response, "status_code", None)
            if status_code is not None:
                span.set_attribute("http.response.status_code", status_code)
                span.set_attribute("http.status_code", status_code)  # legacy
                if status_code >= 500:
                    span.set_status(Status(StatusCode.ERROR))

            return response
    finally:
        otel_context.detach(token)
