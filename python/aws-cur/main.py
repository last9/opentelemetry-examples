"""
AWS Cost and Usage Report (CUR) → OpenTelemetry Pipeline

Reads CUR parquet files from S3, aggregates daily costs by service/account/region,
and exports as OTLP gauge metrics to Last9.

Metrics exported:
  aws.cost.unblended  (USD) — daily unblended cost per service/account/region
  aws.cost.amortized  (USD) — daily amortized cost (includes RI/SP effective cost)
  aws.usage.quantity        — daily usage amount per service/account/region/usage_type

Cost allocation tags from CUR (resource_tags_user_*) are forwarded as aws.tag.*
metric attributes. Configure which tags to include via COST_ALLOCATION_TAGS.

CUR setup required:
  1. Enable Cost and Usage Reports in AWS Billing → Cost & Usage Reports
  2. Format: Parquet, Time granularity: Daily, S3 destination configured
  3. Enable cost allocation tags you want in AWS Billing → Cost allocation tags
  4. Set CUR_S3_BUCKET, CUR_S3_PREFIX, CUR_REPORT_NAME env vars

Historical timestamps are written directly via OTLP/HTTP JSON so each data
point carries the actual billing date, not the current time.
"""

from __future__ import annotations

import io
import json
import logging
import os
import signal
import time
from datetime import datetime, timezone
from typing import Any

import boto3
import pandas as pd
import pyarrow.parquet as pq
import requests

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

# ── Configuration ──────────────────────────────────────────────────────────────

CUR_S3_BUCKET = os.environ["CUR_S3_BUCKET"]
CUR_S3_PREFIX = os.environ.get("CUR_S3_PREFIX", "").strip("/")
CUR_REPORT_NAME = os.environ["CUR_REPORT_NAME"]
AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")

POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL_SECONDS", "3600"))
MONTHS_BACK = int(os.environ.get("MONTHS_BACK", "3"))

OTLP_ENDPOINT = os.environ.get("OTLP_ENDPOINT", "https://otlp.last9.io")
OTLP_HEADERS_RAW = os.environ.get("OTLP_HEADERS", "")
OTEL_SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "aws-cost-reporter")

# Line item types to include — excludes Tax, Credit, Refund, etc.
INCLUDE_LINE_ITEM_TYPES = frozenset(
    os.environ.get(
        "INCLUDE_LINE_ITEM_TYPES",
        "Usage,SavingsPlanCoveredUsage,DiscountedUsage,SavingsPlanNegation,BundledDiscount",
    ).split(",")
)

# Cost allocation tag keys to include as metric dimensions (aws.tag.<key>).
# Must match tags enabled in AWS Billing → Cost allocation tags.
# Example: COST_ALLOCATION_TAGS=team,environment,project
COST_ALLOCATION_TAGS: list[str] = [
    t.strip()
    for t in os.environ.get("COST_ALLOCATION_TAGS", "").split(",")
    if t.strip()
]

# ── Helpers ────────────────────────────────────────────────────────────────────


def _parse_headers(raw: str) -> dict[str, str]:
    headers: dict[str, str] = {}
    for pair in raw.split(","):
        if "=" in pair:
            k, v = pair.split("=", 1)
            headers[k.strip()] = v.strip()
    return headers


def _date_to_ns(date_str: str) -> str:
    """Convert YYYY-MM-DD to Unix nanosecond string for OTLP."""
    dt = datetime.strptime(date_str, "%Y-%m-%d").replace(hour=12, tzinfo=timezone.utc)
    return str(int(dt.timestamp() * 1_000_000_000))


# ── S3 / CUR reading ───────────────────────────────────────────────────────────


def _report_prefix() -> str:
    parts = [p for p in [CUR_S3_PREFIX, CUR_REPORT_NAME] if p]
    return "/".join(parts) + "/"


def list_billing_periods(s3: Any) -> list[str]:
    """Return S3 key prefixes for billing period folders, newest first."""
    prefix = _report_prefix()
    paginator = s3.get_paginator("list_objects_v2")
    folders: set[str] = set()
    for page in paginator.paginate(Bucket=CUR_S3_BUCKET, Prefix=prefix, Delimiter="/"):
        for cp in page.get("CommonPrefixes", []):
            folders.add(cp["Prefix"])
    return sorted(folders, reverse=True)


def load_manifest(s3: Any, period_prefix: str) -> dict:
    key = f"{period_prefix}{CUR_REPORT_NAME}-Manifest.json"
    obj = s3.get_object(Bucket=CUR_S3_BUCKET, Key=key)
    return json.loads(obj["Body"].read())


def read_cur_parquet(s3: Any, manifest: dict) -> pd.DataFrame:
    """Download and concatenate all parquet chunks for one billing period."""
    dfs: list[pd.DataFrame] = []
    for key in manifest.get("reportKeys", []):
        log.info("  Reading s3://%s/%s", CUR_S3_BUCKET, key)
        obj = s3.get_object(Bucket=CUR_S3_BUCKET, Key=key)
        buf = io.BytesIO(obj["Body"].read())
        dfs.append(pq.read_table(buf).to_pandas())
    if not dfs:
        return pd.DataFrame()
    return pd.concat(dfs, ignore_index=True)


# ── Column normalization ───────────────────────────────────────────────────────

# CUR parquet may use either "line_item/ProductCode" or "line_item_product_code"
# as column names depending on the CUR export version. Normalize to snake_case.
_COL_ALIASES: dict[str, str] = {
    "line_item/productcode": "line_item_product_code",
    "line_item/usagestartdate": "line_item_usage_start_date",
    "line_item/usageaccountid": "line_item_usage_account_id",
    "line_item/lineitemtype": "line_item_line_item_type",
    "line_item/unblendedcost": "line_item_unblended_cost",
    "line_item/usageamount": "line_item_usage_amount",
    "line_item/usagetype": "line_item_usage_type",
    "product/region": "product_region",
}


def _normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    rename = {}
    for col in df.columns:
        normalized = col.lower().replace("/", "_")
        if normalized != col:
            rename[col] = normalized
        # Also handle slash-containing names
        alias = col.lower().replace("_", "").replace("/", "")
        for src, dst in _COL_ALIASES.items():
            if src.replace("_", "").replace("/", "") == alias:
                rename[col] = dst
                break
    return df.rename(columns=rename) if rename else df


# ── Aggregation ────────────────────────────────────────────────────────────────

_REQUIRED_COLS = {
    "line_item_usage_start_date",
    "line_item_product_code",
    "line_item_usage_account_id",
    "product_region",
    "line_item_line_item_type",
    "line_item_unblended_cost",
    "line_item_usage_amount",
    "line_item_usage_type",
}

# Per-type column that holds the true effective cost for amortized calculation.
# SavingsPlanCoveredUsage → SP effective cost; DiscountedUsage → RI effective cost.
_AMORTIZED_COL_BY_TYPE: dict[str, str] = {
    "SavingsPlanCoveredUsage": "savings_plan_savings_plan_effective_cost",
    "DiscountedUsage": "reservation_effective_cost",
}


def _compute_amortized(df: pd.DataFrame) -> pd.Series:
    """Return per-row amortized cost using SP/RI effective cost where applicable."""
    result = df["line_item_unblended_cost"].copy()
    for item_type, col in _AMORTIZED_COL_BY_TYPE.items():
        if col in df.columns:
            mask = df["line_item_line_item_type"] == item_type
            result.loc[mask] = pd.to_numeric(df.loc[mask, col], errors="coerce").fillna(0.0)
    return result


def _tag_col(tag_key: str) -> str:
    """Map a cost allocation tag key to its CUR parquet column name."""
    return f"resource_tags_user_{tag_key.lower().replace('-', '_').replace(' ', '_')}"


def aggregate_costs(df: pd.DataFrame) -> pd.DataFrame:
    """
    Group by date/service/account/region/usage_type (+ configured tags) and sum costs.
    Returns DataFrame with columns:
      date, service, account_id, region, usage_type,
      unblended_cost, amortized_cost, usage_quantity,
      [aws_tag_<key> for each COST_ALLOCATION_TAGS entry]
    """
    df = _normalize_columns(df)

    missing = _REQUIRED_COLS - set(df.columns)
    if missing:
        log.warning("CUR missing expected columns: %s", missing)
        for col in missing:
            df[col] = None

    df = df[df["line_item_line_item_type"].isin(INCLUDE_LINE_ITEM_TYPES)].copy()

    df["date"] = pd.to_datetime(df["line_item_usage_start_date"]).dt.strftime("%Y-%m-%d")
    df["line_item_unblended_cost"] = (
        pd.to_numeric(df["line_item_unblended_cost"], errors="coerce").fillna(0.0)
    )
    df["line_item_usage_amount"] = (
        pd.to_numeric(df["line_item_usage_amount"], errors="coerce").fillna(0.0)
    )
    df["amortized_cost"] = _compute_amortized(df)

    # Resolve which tag columns exist in this CUR file
    tag_cols: list[str] = []
    tag_col_map: dict[str, str] = {}  # cur_col → output_col
    for tag_key in COST_ALLOCATION_TAGS:
        cur_col = _tag_col(tag_key)
        if cur_col in df.columns:
            out_col = f"aws_tag_{tag_key.lower().replace('-', '_')}"
            tag_cols.append(cur_col)
            tag_col_map[cur_col] = out_col
        else:
            log.warning("Cost allocation tag column not found in CUR: %s (tag: %s)", cur_col, tag_key)

    group_cols = [
        "date",
        "line_item_product_code",
        "line_item_usage_account_id",
        "product_region",
        "line_item_usage_type",
        *tag_cols,
    ]

    agg = (
        df.groupby(group_cols, dropna=False)
        .agg(
            unblended_cost=("line_item_unblended_cost", "sum"),
            amortized_cost=("amortized_cost", "sum"),
            usage_quantity=("line_item_usage_amount", "sum"),
        )
        .reset_index()
        .rename(columns={
            "line_item_product_code": "service",
            "line_item_usage_account_id": "account_id",
            "product_region": "region",
            "line_item_usage_type": "usage_type",
            **tag_col_map,
        })
    )
    return agg


# ── OTLP export ────────────────────────────────────────────────────────────────


def _row_attrs(row: dict) -> list[dict]:
    attrs = []
    for key, val in [
        ("aws.service", row.get("service", "")),
        ("aws.account.id", row.get("account_id", "")),
        ("aws.region", row.get("region", "")),
        ("aws.usage.type", row.get("usage_type", "")),
    ]:
        if val and str(val) not in ("", "nan", "None"):
            attrs.append({"key": key, "value": {"stringValue": str(val)}})
    # Forward cost allocation tags as aws.tag.<key>
    for col, val in row.items():
        if col.startswith("aws_tag_") and val and str(val) not in ("", "nan", "None"):
            attr_key = "aws.tag." + col[len("aws_tag_"):]
            attrs.append({"key": attr_key, "value": {"stringValue": str(val)}})
    return attrs


def send_otlp_metrics(agg: pd.DataFrame) -> None:
    if agg.empty:
        log.info("No rows to export")
        return

    cost_dps: list[dict] = []
    amortized_dps: list[dict] = []
    usage_dps: list[dict] = []

    for _, row in agg.iterrows():
        time_ns = _date_to_ns(row["date"])
        attrs = _row_attrs(row.to_dict())
        unblended = float(row["unblended_cost"])
        amortized = float(row["amortized_cost"])
        qty = float(row["usage_quantity"])
        if unblended != 0.0:
            cost_dps.append({"attributes": attrs, "timeUnixNano": time_ns, "asDouble": unblended})
        if amortized != 0.0:
            amortized_dps.append({"attributes": attrs, "timeUnixNano": time_ns, "asDouble": amortized})
        if qty != 0.0:
            usage_dps.append({"attributes": attrs, "timeUnixNano": time_ns, "asDouble": qty})

    metrics: list[dict] = []
    if cost_dps:
        metrics.append({
            "name": "aws.cost.unblended",
            "unit": "USD",
            "description": "Daily unblended AWS cost by service, account, and region",
            "gauge": {"dataPoints": cost_dps},
        })
    if amortized_dps:
        metrics.append({
            "name": "aws.cost.amortized",
            "unit": "USD",
            "description": "Daily amortized AWS cost including RI and Savings Plan effective rates",
            "gauge": {"dataPoints": amortized_dps},
        })
    if usage_dps:
        metrics.append({
            "name": "aws.usage.quantity",
            "unit": "1",
            "description": "Daily AWS usage amount by service, account, region, and usage type",
            "gauge": {"dataPoints": usage_dps},
        })

    if not metrics:
        return

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
                "scope": {"name": "aws.cur", "version": "1.0.0"},
                "metrics": metrics,
            }],
        }]
    }

    hdrs = {**_parse_headers(OTLP_HEADERS_RAW), "Content-Type": "application/json"}
    resp = requests.post(
        f"{OTLP_ENDPOINT.rstrip('/')}/v1/metrics",
        json=payload,
        headers=hdrs,
        timeout=60,
    )
    if resp.status_code not in (200, 204):
        log.warning("OTLP export failed: HTTP %s — %s", resp.status_code, resp.text[:200])
    else:
        log.info("Exported %d unblended + %d amortized + %d usage data points to Last9",
                 len(cost_dps), len(amortized_dps), len(usage_dps))


# ── Poll loop ──────────────────────────────────────────────────────────────────


def poll(s3: Any) -> None:
    periods = list_billing_periods(s3)
    if not periods:
        log.warning("No billing period folders found at s3://%s/%s", CUR_S3_BUCKET, _report_prefix())
        return

    for period_prefix in periods[:MONTHS_BACK]:
        try:
            manifest = load_manifest(s3, period_prefix)
            billing_start = manifest.get("billingPeriod", {}).get("start", period_prefix)
            log.info("Billing period: %s (%d file(s))",
                     billing_start, len(manifest.get("reportKeys", [])))

            df = read_cur_parquet(s3, manifest)
            if df.empty:
                log.info("  No data in period %s", period_prefix)
                continue

            log.info("  Loaded %d rows, aggregating…", len(df))
            agg = aggregate_costs(df)
            log.info("  Aggregated to %d rows", len(agg))
            send_otlp_metrics(agg)

        except s3.exceptions.NoSuchKey:
            log.warning("Manifest not found for %s — CUR may still be generating", period_prefix)
        except Exception as exc:  # noqa: BLE001
            log.error("Error processing %s: %s", period_prefix, exc)


def main() -> None:
    log.info("AWS CUR collector starting")
    log.info("Bucket         : %s", CUR_S3_BUCKET)
    log.info("Prefix         : %s", CUR_S3_PREFIX or "(root)")
    log.info("Report name    : %s", CUR_REPORT_NAME)
    log.info("Months back    : %d", MONTHS_BACK)
    log.info("Poll interval  : %ds", POLL_INTERVAL_SECONDS)
    log.info("OTLP endpoint  : %s", OTLP_ENDPOINT)

    s3 = boto3.client("s3", region_name=AWS_REGION)

    def _shutdown(sig, _frame):
        log.info("Shutting down…")
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    while True:
        poll(s3)
        log.info("Sleeping %ds…", POLL_INTERVAL_SECONDS)
        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
