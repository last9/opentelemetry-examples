from fastapi import FastAPI
import uvicorn
import time
import random

app = FastAPI(title="Trace Filtering Demo")


# Health check — high-frequency, non-actionable. Excluded via OTEL_PYTHON_EXCLUDED_URLS.
@app.get("/health-check")
async def health_check():
    return {"status": "ok"}


@app.get("/")
async def root():
    return {"message": "Trace filtering demo running"}


@app.get("/api/orders")
async def list_orders():
    time.sleep(random.uniform(0.01, 0.05))
    return {"orders": [{"id": "ord-1", "amount": 42.0}, {"id": "ord-2", "amount": 99.0}]}


@app.get("/api/orders/{order_id}")
async def get_order(order_id: str):
    time.sleep(random.uniform(0.005, 0.02))
    return {"id": order_id, "amount": 42.0, "status": "shipped"}


@app.post("/api/orders")
async def create_order(item: dict):
    time.sleep(random.uniform(0.02, 0.08))
    return {"id": "ord-new", "status": "created"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
