from chalicelib.otel_init import init_otel

init_otel(service_name="chalice-adot-e")

import asyncio
import logging

import aiohttp
import filetype
import requests
from chalice import Chalice

from chalicelib.server_span import server_span_middleware

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

app = Chalice(app_name="chalice-adot-e")
app.register_middleware(server_span_middleware, event_type="all")


@app.route("/")
def index():
    return {
        "filetype_version": filetype.__version__
        if hasattr(filetype, "__version__")
        else "unknown",
        "aiohttp_version": aiohttp.__version__,
    }


@app.route("/outbound")
def outbound():
    """Exercises both requests (sync) and aiohttp (async) instrumentation to
    generate client spans. httpbin.org is a public no-auth echo endpoint."""
    logger.info("outbound: sync GET via requests")
    r1 = requests.get("https://httpbin.org/get", params={"src": "requests"}, timeout=5)

    logger.info("outbound: async GET via aiohttp")
    async def _aio_get() -> int:
        async with aiohttp.ClientSession() as session:
            async with session.get("https://httpbin.org/get", params={"src": "aiohttp"}) as resp:
                return resp.status
    r2_status = asyncio.run(_aio_get())

    return {"requests_status": r1.status_code, "aiohttp_status": r2_status}
