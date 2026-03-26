from chalice import Chalice, Rate
from opentelemetry import trace

app = Chalice(app_name="otel-chalice-example")
tracer = trace.get_tracer(__name__)


@app.middleware("all")
def otel_attributes(event, get_response):
    """Add custom attributes to the current ADOT-created span."""
    span = trace.get_current_span()
    if span.is_recording():
        span.set_attribute("app.framework", "chalice")
    return get_response(event)


@app.route("/")
def index():
    return {"service": "otel-chalice-example", "status": "ok"}


@app.route("/items/{item_id}", methods=["GET"])
def get_item(item_id):
    with tracer.start_as_current_span("lookup_item") as span:
        span.set_attribute("item.id", item_id)
        # Replace with actual DB/API lookup
        item = {"id": item_id, "name": f"Item {item_id}", "quantity": 42}
    return item


@app.route("/items", methods=["POST"])
def create_item():
    body = app.current_request.json_body
    with tracer.start_as_current_span("create_item") as span:
        span.set_attribute("item.name", body.get("name", "unknown"))
        # Replace with actual creation logic
        result = {"id": "new-123", **body}
    return result


@app.schedule(Rate(5, unit=Rate.MINUTES))
def periodic_check(event):
    """Scheduled task - also auto-instrumented by ADOT."""
    with tracer.start_as_current_span("periodic_health_check"):
        pass
    return {"status": "healthy"}
