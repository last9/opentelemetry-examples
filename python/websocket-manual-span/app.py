import asyncio
import os
from urllib.parse import urlsplit, urlunsplit

import websockets
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace import SpanKind, Status, StatusCode


def configure_tracing() -> TracerProvider:
    provider = TracerProvider(
        resource=Resource.create(
            {SERVICE_NAME: os.getenv("OTEL_SERVICE_NAME", "websocket-manual-span")}
        )
    )
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)
    return provider


def sanitized_url(url: str) -> str:
    parts = urlsplit(url)
    return urlunsplit((parts.scheme, parts.netloc, parts.path, "", ""))


async def connect_websocket(url: str, **connect_kwargs):
    parts = urlsplit(url)
    if parts.scheme not in {"ws", "wss"} or not parts.hostname:
        raise ValueError("WEBSOCKET_URL must be a ws:// or wss:// URL with a host")

    port = parts.port or (443 if parts.scheme == "wss" else 80)
    safe_url = sanitized_url(url)
    tracer = trace.get_tracer("websocket-manual-span")

    # End the span after the HTTP upgrade, not when the long-lived socket closes.
    with tracer.start_as_current_span(
        f"GET {parts.hostname}", kind=SpanKind.CLIENT
    ) as span:
        # Current and legacy HTTP attributes keep the endpoint queryable across backends.
        span.set_attribute("http.request.method", "GET")
        span.set_attribute("http.method", "GET")
        span.set_attribute("url.full", safe_url)
        span.set_attribute("http.url", safe_url)
        span.set_attribute("server.address", parts.hostname)
        span.set_attribute("server.port", port)
        span.set_attribute("net.peer.name", parts.hostname)
        span.set_attribute("net.peer.port", port)
        span.set_attribute("network.protocol.name", "websocket")

        try:
            websocket = await websockets.connect(url, **connect_kwargs)
        except Exception as exc:
            span.set_attribute("error.type", type(exc).__name__)
            span.set_status(Status(StatusCode.ERROR))
            raise

        span.set_attribute("http.response.status_code", 101)
        span.set_attribute("http.status_code", 101)
        return websocket


async def main() -> None:
    provider = configure_tracing()
    websocket = None

    try:
        websocket = await connect_websocket(os.environ["WEBSOCKET_URL"])
        await websocket.send(os.getenv("WEBSOCKET_MESSAGE", "hello"))
        print(await websocket.recv())
    finally:
        if websocket is not None:
            await websocket.close()
        provider.force_flush()
        provider.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
