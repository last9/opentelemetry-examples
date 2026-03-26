import logging

import httpx
from fastmcp import FastMCP
from opentelemetry.trace import StatusCode

# Custom spans inside tool handlers
from fastmcp.telemetry import get_tracer

# Structured logging with trace context injection.
# When OTEL_LOGS_EXPORTER=otlp is set, opentelemetry-instrument patches the
# logging module so that every log record includes trace_id and span_id fields
# automatically — no manual wiring needed.
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [%(name)s] %(message)s")
logger = logging.getLogger("notes-server")

mcp = FastMCP("notes-server")

# In-memory notes storage
notes: dict[str, str] = {}


@mcp.tool()
async def add_note(title: str, content: str) -> str:
    """Add a new note."""
    tracer = get_tracer()
    with tracer.start_as_current_span("validate_note") as span:
        span.set_attribute("note.title", title)
        if not title.strip():
            span.set_status(StatusCode.ERROR, "empty title")
            logger.warning("add_note failed: empty title")
            return "Error: title cannot be empty"
        if title in notes:
            span.set_status(StatusCode.ERROR, "duplicate title")
            logger.warning("add_note failed: duplicate title '%s'", title)
            return f"Error: note '{title}' already exists. Use update_note instead."

    notes[title] = content
    logger.info("Note '%s' added", title)
    return f"Note '{title}' added successfully."


@mcp.tool()
async def update_note(title: str, content: str) -> str:
    """Update an existing note."""
    if title not in notes:
        logger.warning("update_note failed: '%s' not found", title)
        return f"Error: note '{title}' not found."
    notes[title] = content
    logger.info("Note '%s' updated", title)
    return f"Note '{title}' updated."


@mcp.tool()
async def delete_note(title: str) -> str:
    """Delete a note by title."""
    if title not in notes:
        logger.warning("delete_note failed: '%s' not found", title)
        return f"Error: note '{title}' not found."
    del notes[title]
    logger.info("Note '%s' deleted", title)
    return f"Note '{title}' deleted."


@mcp.tool()
async def search_notes(query: str) -> str:
    """Search notes by keyword in title or content."""
    tracer = get_tracer()
    with tracer.start_as_current_span("search_notes_scan") as span:
        span.set_attribute("search.query", query)
        span.set_attribute("search.corpus_size", len(notes))
        matches = {
            title: content
            for title, content in notes.items()
            if query.lower() in title.lower() or query.lower() in content.lower()
        }
        span.set_attribute("search.results_count", len(matches))

    if not matches:
        return f"No notes matching '{query}'."
    return "\n\n".join(f"## {t}\n{c}" for t, c in matches.items())


@mcp.tool()
async def fetch_url(url: str) -> str:
    """Fetch a URL and return its text content.

    httpx calls are auto-instrumented by opentelemetry-instrument,
    so you get child spans for every HTTP request for free.
    """
    tracer = get_tracer()
    with tracer.start_as_current_span("fetch_url_request") as span:
        span.set_attribute("http.url", url)
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.get(url, follow_redirects=True, timeout=10)
                resp.raise_for_status()
                body = resp.text[:2000]
                span.set_attribute("http.status_code", resp.status_code)
                logger.info("Fetched %s — %d bytes", url, len(body))
                return body
        except httpx.HTTPStatusError as exc:
            span.record_exception(exc)
            span.set_status(StatusCode.ERROR, f"HTTP {exc.response.status_code}")
            logger.error("fetch_url HTTP error: %s", exc)
            return f"Error: HTTP {exc.response.status_code} for {url}"
        except httpx.RequestError as exc:
            span.record_exception(exc)
            span.set_status(StatusCode.ERROR, str(exc))
            logger.error("fetch_url request error: %s", exc)
            return f"Error: {exc}"


@mcp.resource("notes://list")
async def list_notes() -> str:
    """List all stored notes."""
    if not notes:
        return "No notes yet."
    return "\n".join(f"- {title}" for title in sorted(notes))


@mcp.resource("notes://{title}")
async def get_note(title: str) -> str:
    """Read a single note by title."""
    if title not in notes:
        return f"Note '{title}' not found."
    return notes[title]
