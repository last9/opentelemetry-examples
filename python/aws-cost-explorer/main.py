"""
AWS Cost Explorer → OpenTelemetry Pipeline

Polls the AWS Cost Explorer API and exports cost metrics to Last9.
No CUR setup or S3 bucket required — data is available within minutes.

Metrics exported:
  aws.cost.unblended  (USD) — daily unblended cost per service/account/region
  aws.cost.amortized  (USD) — daily amortized cost (includes RI/SP effective rates)

Deployment modes:
  Lambda  — deploy with deploy.sh; EventBridge triggers daily (recommended)
  Docker  — docker compose up (for local testing or non-AWS environments)
"""

from __future__ import annotations

import logging
import os
import signal
import time
from datetime import date, timedelta, timezone, datetime

import boto3
import requests

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

# ── Configuration ──────────────────────────────────────────────────────────────

AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
DAYS_BACK = int(os.environ.get("DAYS_BACK", "30"))
POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL_SECONDS", "86400"))

OTLP_ENDPOINT = os.environ.get("OTLP_ENDPOINT", "https://otlp.last9.io")
OTLP_HEADERS_RAW = os.environ.get("OTLP_HEADERS", "")
OTEL_SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "aws-cost-reporter")

# ── Helpers ────────────────────────────────────────────────────────────────────


def _parse_headers(raw: str) -> dict[str, str]:
    headers: dict[str, str] = {}
    for pair in raw.split(","):
        if "=" in pair:
            k, v = pair.split("=", 1)
            headers[k.strip()] = v.strip()
    return headers


def _date_to_ns(date_str: str) -> str:
    dt = datetime.strptime(date_str, "%Y-%m-%d").replace(hour=12, tzinfo=timezone.utc)
    return str(int(dt.timestamp() * 1_000_000_000))


# ── Cost Explorer fetch ────────────────────────────────────────────────────────


def fetch_costs(ce: object) -> list[dict]:
    """
    Fetch daily costs grouped by SERVICE, LINKED_ACCOUNT, REGION.
    Returns flat list of {date, service, account_id, region, unblended, amortized}.
    """
    end = date.today()
    start = end - timedelta(days=DAYS_BACK)

    rows: list[dict] = []
    next_token: str | None = None

    while True:
        kwargs: dict = {
            "TimePeriod": {"Start": str(start), "End": str(end)},
            "Granularity": "DAILY",
            "Metrics": ["UnblendedCost", "AmortizedCost"],
            "GroupBy": [
                {"Type": "DIMENSION", "Key": "SERVICE"},
                {"Type": "DIMENSION", "Key": "LINKED_ACCOUNT"},
                {"Type": "DIMENSION", "Key": "REGION"},
            ],
        }
        if next_token:
            kwargs["NextPageToken"] = next_token

        resp = ce.get_cost_and_usage(**kwargs)

        for result in resp.get("ResultsByTime", []):
            day = result["TimePeriod"]["Start"]
            for group in result.get("Groups", []):
                service, account_id, region = group["Keys"]
                unblended = float(group["Metrics"]["UnblendedCost"]["Amount"])
                amortized = float(group["Metrics"]["AmortizedCost"]["Amount"])
                if unblended == 0.0 and amortized == 0.0:
                    continue
                rows.append({
                    "date": day,
                    "service": service,
                    "account_id": account_id,
                    "region": region,
                    "unblended": unblended,
                    "amortized": amortized,
                })

        next_token = resp.get("NextPageToken")
        if not next_token:
            break

    log.info("Fetched %d cost rows (%s → %s)", len(rows), start, end)
    return rows


# ── OTLP export ────────────────────────────────────────────────────────────────


def send_otlp_metrics(rows: list[dict]) -> None:
    if not rows:
        log.info("No cost rows to export")
        return

    unblended_dps: list[dict] = []
    amortized_dps: list[dict] = []

    for row in rows:
        time_ns = _date_to_ns(row["date"])
        attrs = [
            {"key": "aws.service", "value": {"stringValue": row["service"]}},
            {"key": "aws.account.id", "value": {"stringValue": row["account_id"]}},
            {"key": "aws.region", "value": {"stringValue": row["region"]}},
        ]
        if row["unblended"] != 0.0:
            unblended_dps.append({"attributes": attrs, "timeUnixNano": time_ns,
                                   "asDouble": row["unblended"]})
        if row["amortized"] != 0.0:
            amortized_dps.append({"attributes": attrs, "timeUnixNano": time_ns,
                                   "asDouble": row["amortized"]})

    metrics = []
    if unblended_dps:
        metrics.append({
            "name": "aws.cost.unblended",
            "unit": "USD",
            "description": "Daily unblended AWS cost by service, account, and region",
            "gauge": {"dataPoints": unblended_dps},
        })
    if amortized_dps:
        metrics.append({
            "name": "aws.cost.amortized",
            "unit": "USD",
            "description": "Daily amortized AWS cost including RI and Savings Plan effective rates",
            "gauge": {"dataPoints": amortized_dps},
        })

    payload = {
        "resourceMetrics": [{
            "resource": {
                "attributes": [
                    {"key": "service.name", "value": {"stringValue": OTEL_SERVICE_NAME}},
                    {"key": "telemetry.sdk.language", "value": {"stringValue": "python"}},
                    {"key": "cloud.provider", "value": {"stringValue": "aws"}},
                ]
            },
            "scopeMetrics": [{
                "scope": {"name": "aws.cost_explorer", "version": "1.0.0"},
                "metrics": metrics,
            }],
        }]
    }

    hdrs = {**_parse_headers(OTLP_HEADERS_RAW), "Content-Type": "application/json"}
    resp = requests.post(
        f"{OTLP_ENDPOINT.rstrip('/')}/v1/metrics",
        json=payload,
        headers=hdrs,
        timeout=30,
    )
    if resp.status_code not in (200, 204):
        log.warning("OTLP export failed: HTTP %s — %s", resp.status_code, resp.text[:200])
    else:
        log.info("Exported %d unblended + %d amortized data points to Last9",
                 len(unblended_dps), len(amortized_dps))


# ── Poll loop ──────────────────────────────────────────────────────────────────


def poll(ce: object) -> None:
    rows = fetch_costs(ce)
    send_otlp_metrics(rows)


def main() -> None:
    log.info("AWS Cost Explorer collector starting")
    log.info("Days back      : %d", DAYS_BACK)
    log.info("Poll interval  : %ds", POLL_INTERVAL_SECONDS)
    log.info("OTLP endpoint  : %s", OTLP_ENDPOINT)

    ce = boto3.client("ce", region_name="us-east-1")  # Cost Explorer is a global service

    def _shutdown(sig, _frame):
        log.info("Shutting down…")
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    while True:
        poll(ce)
        log.info("Sleeping %ds…", POLL_INTERVAL_SECONDS)
        time.sleep(POLL_INTERVAL_SECONDS)


# ── Lambda handler ─────────────────────────────────────────────────────────────


def lambda_handler(event: dict, context: object) -> dict:
    """Entry point for AWS Lambda (triggered by EventBridge schedule)."""
    ce = boto3.client("ce", region_name="us-east-1")
    rows = fetch_costs(ce)
    send_otlp_metrics(rows)
    return {"statusCode": 200, "exported": len(rows)}


if __name__ == "__main__":
    main()
