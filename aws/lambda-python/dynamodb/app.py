import os
import uuid

import boto3
from chalice import Chalice, NotFoundError, BadRequestError
from opentelemetry import trace

app = Chalice(app_name="lambda-dynamodb-otel")
tracer = trace.get_tracer(__name__)

TABLE_NAME = os.environ.get("DYNAMODB_TABLE", "items")
AWS_REGION = os.environ.get("AWS_REGION", "ap-south-1")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table = dynamodb.Table(TABLE_NAME)


@app.middleware("all")
def otel_attributes(event, get_response):
    """Enrich the ADOT-created span with app-level attributes."""
    span = trace.get_current_span()
    if span.is_recording():
        span.set_attribute("app.framework", "chalice")
        span.set_attribute("app.table", TABLE_NAME)
    return get_response(event)


@app.route("/items", methods=["GET"])
def list_items():
    """Scan the DynamoDB table — auto-instrumented by ADOT botocore layer."""
    with tracer.start_as_current_span("list_items") as span:
        result = table.scan()
        items = result.get("Items", [])
        span.set_attribute("dynamodb.items_returned", len(items))
    return {"items": items, "count": len(items)}


@app.route("/items/{item_id}", methods=["GET"])
def get_item(item_id):
    """Fetch a single item by ID — DynamoDB.GetItem span created automatically."""
    with tracer.start_as_current_span("get_item") as span:
        span.set_attribute("item.id", item_id)
        result = table.get_item(Key={"id": item_id})
        item = result.get("Item")
        if not item:
            raise NotFoundError(f"Item {item_id!r} not found")
    return item


@app.route("/items", methods=["POST"])
def create_item():
    """Create a new item — DynamoDB.PutItem span created automatically."""
    body = app.current_request.json_body
    if not body or "name" not in body:
        raise BadRequestError("Request body must include 'name'")

    item = {
        "id": str(uuid.uuid4()),
        "name": body["name"],
        "description": body.get("description", ""),
    }

    with tracer.start_as_current_span("create_item") as span:
        span.set_attribute("item.name", item["name"])
        table.put_item(Item=item)

    return item


@app.route("/items/{item_id}", methods=["DELETE"])
def delete_item(item_id):
    """Delete an item — DynamoDB.DeleteItem span created automatically."""
    with tracer.start_as_current_span("delete_item") as span:
        span.set_attribute("item.id", item_id)
        table.delete_item(Key={"id": item_id})
    return {"deleted": item_id}
