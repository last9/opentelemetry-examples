"""
Custom sampler approach for span filtering.

Use this when you need filtering logic beyond URL pattern matching:
- filter by span attributes (status code, user type, tenant)
- combine URL exclusion with ratio sampling
- conditional sampling based on business logic

For simple URL exclusion, prefer OTEL_PYTHON_EXCLUDED_URLS — no code needed.
"""

from opentelemetry.sdk.trace.sampling import (
    Sampler,
    SamplingResult,
    Decision,
    ALWAYS_ON,
    ParentBased,
)
from opentelemetry.trace import SpanKind
from opentelemetry.context import Context
from opentelemetry.trace.span import TraceState
from typing import Optional, Sequence

EXCLUDED_URL_PATTERNS = {"/health-check", "/health", "/ping", "/ready", "/live", "/metrics"}


class DropNoisySpansSampler(Sampler):
    """
    Drops spans for excluded URL paths and error-free 2xx responses.
    Preserves all error spans regardless of URL.
    """

    def should_sample(
        self,
        parent_context: Optional[Context],
        trace_id: int,
        name: str,
        kind: Optional[SpanKind] = None,
        attributes=None,
        links=None,
        trace_state: Optional[TraceState] = None,
    ) -> SamplingResult:
        if attributes:
            # OTel semconv v1: http.target  |  v2: url.path
            path = attributes.get("http.target") or attributes.get("url.path") or ""
            status = attributes.get("http.status_code") or attributes.get("http.response.status_code")

            is_excluded_path = any(path.startswith(p) for p in EXCLUDED_URL_PATTERNS)

            # Always keep error spans — they're actionable even on health endpoints
            is_error = status is not None and int(status) >= 500
            if is_excluded_path and not is_error:
                return SamplingResult(Decision.DROP)

        return ALWAYS_ON.should_sample(
            parent_context, trace_id, name, kind, attributes, links, trace_state
        )

    def get_description(self) -> str:
        return "DropNoisySpansSampler"


# ParentBased wrapper: child spans inherit DROP from root span.
# Without this, a dropped root still creates orphaned child spans.
sampler = ParentBased(root=DropNoisySpansSampler())
