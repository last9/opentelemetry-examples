"""Cerebrium app — zero OpenTelemetry code.

All tracing is wired by `opentelemetry-instrument` in the entrypoint
(see cerebrium.toml). FastAPI, requests, and httpx are auto-patched.
"""

import logging
import time

import requests
from fastapi import FastAPI
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

app = FastAPI()


class PredictRequest(BaseModel):
    prompt: str = "hello world"
    run_id: str | None = None


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/ready")
def ready():
    return {"status": "ok"}


@app.post("/predict")
def predict(req: PredictRequest):
    log.info("predict: prompt_len=%d run_id=%s", len(req.prompt), req.run_id)
    start = time.perf_counter()
    statuses = []
    for url in ("https://httpbin.org/uuid", "https://httpbin.org/headers"):
        try:
            r = requests.get(url, timeout=5)
            statuses.append(r.status_code)
        except Exception as e:
            log.warning("downstream call failed: url=%s err=%s", url, e)
            statuses.append(-1)
    latency_ms = (time.perf_counter() - start) * 1000.0
    log.info("predict: done in %.1fms statuses=%s", latency_ms, statuses)
    return {
        "prompt": req.prompt,
        "downstream_status": statuses,
        "latency_ms": round(latency_ms, 2),
    }
