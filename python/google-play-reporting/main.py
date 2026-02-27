"""
Google Play Developer Reporting API → OpenTelemetry Pipeline

Polls all Android vitals metric sets from the Play Developer Reporting API
and exports them as OTLP gauge metrics + anomaly log events.

Each API row carries a startTime (the measurement date). We POST OTLP/HTTP JSON
directly — bypassing the OTel SDK gauge abstraction — so every row is exported
as a distinct data point with its correct historical timestamp.

Metric sets covered:
  - crashRateMetricSet         (daily)
  - anrRateMetricSet           (daily)
  - slowRenderingRateMetricSet (daily)
  - slowStartRateMetricSet     (daily, startType dimension required)
  - excessiveWakeupRateMetricSet  (daily)
  - stuckBackgroundWakelockRateMetricSet (daily)
  - lmkRateMetricSet           (daily — Low Memory Kill)
  - errorCountMetricSet        (hourly — leading indicator, 2-4h lag)
  - anomalies                  → exported as OTel WARN log records

Data freshness: daily metrics lag 24-48h; hourly metrics lag ~2-4h.
"""

from __future__ import annotations

import logging
import os
import signal
import time
from datetime import date, datetime, timedelta, timezone
from typing import Any

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account
from opentelemetry._logs import SeverityNumber, set_logger_provider
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.resources import Resource

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

# ── Configuration ─────────────────────────────────────────────────────────────

GOOGLE_APPLICATION_CREDENTIALS = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")

PACKAGE_NAMES = [
    p.strip()
    for p in os.environ.get("ANDROID_PACKAGE_NAMES", "com.example.app").split(",")
    if p.strip()
]

POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL_SECONDS", "1800"))
POLL_DAYS_BACK = int(os.environ.get("POLL_DAYS_BACK", "30"))
ENABLE_HOURLY = os.environ.get("ENABLE_HOURLY", "false").lower() == "true"

OTLP_ENDPOINT = os.environ.get("OTLP_ENDPOINT", "https://otlp.last9.io")
OTLP_HEADERS_RAW = os.environ.get("OTLP_HEADERS", "")
OTEL_SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "google-play-reporting")

_raw_dims = os.environ.get("ANDROID_DIMENSIONS", "")
DIMENSIONS: list[str] = [d.strip() for d in _raw_dims.split(",") if d.strip()]

REPORTING_API_BASE = "https://playdeveloperreporting.googleapis.com/v1beta1"
SCOPES = ["https://www.googleapis.com/auth/playdeveloperreporting"]

# ── Metric catalogue ──────────────────────────────────────────────────────────
# Maps: metric_set → { api_metric_name → (otel_name, unit, description) }

METRIC_CATALOGUE: dict[str, dict[str, tuple[str, str, str]]] = {
    "crashRateMetricSet": {
        "crashRate": ("android.vitals.crash_rate", "1",
                      "Daily crash rate (fraction of sessions with a crash)"),
        "crashRate7dUserWeighted": ("android.vitals.crash_rate_7d", "1",
                                    "7-day user-weighted crash rate"),
        "crashRate28dUserWeighted": ("android.vitals.crash_rate_28d", "1",
                                     "28-day user-weighted crash rate"),
        "userPerceivedCrashRate": ("android.vitals.user_perceived_crash_rate", "1",
                                   "Foreground crash rate (user-visible crashes only)"),
        "userPerceivedCrashRate7dUserWeighted": ("android.vitals.user_perceived_crash_rate_7d",
                                                 "1", "7-day user-perceived crash rate"),
        "userPerceivedCrashRate28dUserWeighted": ("android.vitals.user_perceived_crash_rate_28d",
                                                  "1", "28-day user-perceived crash rate"),
        "distinctUsers": ("android.vitals.crash_distinct_users", "{user}",
                          "Distinct users in the crash rate denominator"),
    },
    "anrRateMetricSet": {
        "anrRate": ("android.vitals.anr_rate", "1", "Daily ANR rate"),
        "anrRate7dUserWeighted": ("android.vitals.anr_rate_7d", "1",
                                  "7-day user-weighted ANR rate"),
        "anrRate28dUserWeighted": ("android.vitals.anr_rate_28d", "1",
                                   "28-day user-weighted ANR rate"),
        "userPerceivedAnrRate": ("android.vitals.user_perceived_anr_rate", "1",
                                 "Foreground ANR rate (user-visible only)"),
        "userPerceivedAnrRate7dUserWeighted": ("android.vitals.user_perceived_anr_rate_7d",
                                               "1", "7-day user-perceived ANR rate"),
        "userPerceivedAnrRate28dUserWeighted": ("android.vitals.user_perceived_anr_rate_28d",
                                                "1", "28-day user-perceived ANR rate"),
        "distinctUsers": ("android.vitals.anr_distinct_users", "{user}",
                          "Distinct users in the ANR rate denominator"),
    },
    "slowRenderingRateMetricSet": {
        "slowRenderingRate20Fps": ("android.vitals.slow_rendering_rate_20fps", "1",
                                   "Sessions with rendering below 20 FPS"),
        "slowRenderingRate20Fps7dUserWeighted": ("android.vitals.slow_rendering_rate_20fps_7d",
                                                 "1", "7-day slow rendering <20fps"),
        "slowRenderingRate30Fps": ("android.vitals.slow_rendering_rate_30fps", "1",
                                   "Sessions with rendering below 30 FPS"),
        "slowRenderingRate30Fps7dUserWeighted": ("android.vitals.slow_rendering_rate_30fps_7d",
                                                 "1", "7-day slow rendering <30fps"),
        "distinctUsers": ("android.vitals.slow_rendering_distinct_users", "{user}",
                          "Distinct users in the slow rendering denominator"),
    },
    "slowStartRateMetricSet": {
        "slowStartRate": ("android.vitals.slow_start_rate", "1",
                          "Fraction of slow app starts (threshold varies by startType)"),
        "slowStartRate7dUserWeighted": ("android.vitals.slow_start_rate_7d", "1",
                                        "7-day slow start rate"),
        "slowStartRate28dUserWeighted": ("android.vitals.slow_start_rate_28d", "1",
                                         "28-day slow start rate"),
        "distinctUsers": ("android.vitals.slow_start_distinct_users", "{user}",
                          "Distinct users in the slow start denominator"),
    },
    "excessiveWakeupRateMetricSet": {
        "excessiveWakeupRate": ("android.vitals.excessive_wakeup_rate", "1",
                                "Sessions with >10 AlarmManager wakeups/hour"),
        "excessiveWakeupRate7dUserWeighted": ("android.vitals.excessive_wakeup_rate_7d", "1",
                                              "7-day excessive wakeup rate"),
        "excessiveWakeupRate28dUserWeighted": ("android.vitals.excessive_wakeup_rate_28d", "1",
                                               "28-day excessive wakeup rate"),
        "distinctUsers": ("android.vitals.excessive_wakeup_distinct_users", "{user}",
                          "Distinct users in the excessive wakeup denominator"),
    },
    "stuckBackgroundWakelockRateMetricSet": {
        "stuckBgWakelockRate": ("android.vitals.stuck_background_wakelock_rate", "1",
                                "Sessions where a background wakelock was held >1 hour"),
        "stuckBgWakelockRate7dUserWeighted": ("android.vitals.stuck_background_wakelock_rate_7d",
                                              "1", "7-day stuck background wakelock rate"),
        "stuckBgWakelockRate28dUserWeighted": ("android.vitals.stuck_background_wakelock_rate_28d",
                                               "1", "28-day stuck background wakelock rate"),
        "distinctUsers": ("android.vitals.stuck_wakelock_distinct_users", "{user}",
                          "Distinct users in the stuck wakelock denominator"),
    },
    "lmkRateMetricSet": {
        "userPerceivedLmkRate": ("android.vitals.lmk_rate", "1",
                                 "Active-use LMK rate (app killed by Android OOM killer)"),
        "userPerceivedLmkRate7dUserWeighted": ("android.vitals.lmk_rate_7d", "1",
                                               "7-day LMK rate"),
        "userPerceivedLmkRate28dUserWeighted": ("android.vitals.lmk_rate_28d", "1",
                                                "28-day LMK rate"),
        "distinctUsers": ("android.vitals.lmk_distinct_users", "{user}",
                          "Distinct users in the LMK denominator"),
    },
    "errorCountMetricSet": {
        "errorReportCount": ("android.vitals.error_report_count", "{error}",
                             "Hourly error report count (leading indicator, ~2-4h lag)"),
        "distinctUsers": ("android.vitals.error_distinct_users", "{user}",
                          "Distinct users with errors in this hour"),
    },
}

# ── Query config ──────────────────────────────────────────────────────────────

DAILY_METRIC_NAMES: dict[str, list[str]] = {
    ms: list(catalogue.keys())
    for ms, catalogue in METRIC_CATALOGUE.items()
    if ms != "errorCountMetricSet"
}

HOURLY_METRIC_NAMES: dict[str, list[str]] = {
    "crashRateMetricSet": ["crashRate", "userPerceivedCrashRate", "distinctUsers"],
    "anrRateMetricSet": ["anrRate", "userPerceivedAnrRate", "distinctUsers"],
}

# slowStartRateMetricSet requires startType as a mandatory extra dimension.
DAILY_REQUIRED_EXTRA_DIMS: dict[str, list[str]] = {
    "slowStartRateMetricSet": ["startType"],
}

# errorCountMetricSet requires reportType and does not support countryCode.
ERROR_COUNT_EXTRA_DIMS = ["reportType"]
ERROR_COUNT_UNSUPPORTED_DIMS = frozenset(["countryCode"])

# ── OTel log provider (anomalies only) ────────────────────────────────────────


def _parse_headers(raw: str) -> dict[str, str]:
    headers: dict[str, str] = {}
    for pair in raw.split(","):
        if "=" in pair:
            k, v = pair.split("=", 1)
            headers[k.strip()] = v.strip()
    return headers


def build_logger_provider() -> LoggerProvider:
    resource = Resource.create({"service.name": OTEL_SERVICE_NAME})
    exporter = OTLPLogExporter(
        endpoint=f"{OTLP_ENDPOINT.rstrip('/')}/v1/logs",
        headers=_parse_headers(OTLP_HEADERS_RAW),
    )
    provider = LoggerProvider(resource=resource)
    provider.add_log_record_processor(BatchLogRecordProcessor(exporter))
    return provider


# ── Google auth ───────────────────────────────────────────────────────────────


def load_credentials() -> service_account.Credentials:
    if not GOOGLE_APPLICATION_CREDENTIALS:
        raise RuntimeError(
            "GOOGLE_APPLICATION_CREDENTIALS is not set. "
            "Point it to the service account JSON file path."
        )
    return service_account.Credentials.from_service_account_file(
        GOOGLE_APPLICATION_CREDENTIALS, scopes=SCOPES
    )


def bearer_token(creds: service_account.Credentials) -> str:
    if not creds.valid:
        creds.refresh(Request())
    return creds.token


# ── API helpers ───────────────────────────────────────────────────────────────


def _to_api_date(d: date) -> dict:
    return {"year": d.year, "month": d.month, "day": d.day}


def _to_api_datetime(dt: datetime) -> dict:
    return {"year": dt.year, "month": dt.month, "day": dt.day,
            "hours": dt.hour, "minutes": dt.minute}


def get_freshness(token: str, package: str, metric_set: str) -> dict[str, date]:
    url = f"{REPORTING_API_BASE}/apps/{package}/{metric_set}"
    resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=15)
    resp.raise_for_status()
    result: dict[str, date] = {}
    for f in resp.json().get("freshnessInfo", {}).get("freshnesses", []):
        period = f.get("aggregationPeriod")
        t = f.get("latestEndTime", {})
        if period and t:
            result[period] = date(t["year"], t["month"], t["day"])
    return result


def query_daily(
    token: str, package: str, metric_set: str, metric_names: list[str],
    end: date, extra_dims: list[str] | None = None, base_dims: list[str] | None = None,
) -> list[dict]:
    start = end - timedelta(days=POLL_DAYS_BACK - 1)
    dims = (base_dims if base_dims is not None else DIMENSIONS) + (extra_dims or [])
    return _post_query(token, package, metric_set, {
        "timelineSpec": {"aggregationPeriod": "DAILY",
                         "startTime": _to_api_date(start), "endTime": _to_api_date(end)},
        "dimensions": dims, "metrics": metric_names, "pageSize": 1000,
    })


def query_hourly(
    token: str, package: str, metric_set: str, metric_names: list[str],
    end: date, extra_dims: list[str] | None = None, base_dims: list[str] | None = None,
) -> list[dict]:
    end_dt = datetime(end.year, end.month, end.day, tzinfo=timezone.utc)
    start_dt = end_dt - timedelta(hours=48)
    dims = (base_dims if base_dims is not None else DIMENSIONS) + (extra_dims or [])
    return _post_query(token, package, metric_set, {
        "timelineSpec": {"aggregationPeriod": "HOURLY",
                         "startTime": _to_api_datetime(start_dt),
                         "endTime": _to_api_datetime(end_dt)},
        "dimensions": dims, "metrics": metric_names, "pageSize": 1000,
    })


def _post_query(token: str, package: str, metric_set: str, payload: dict) -> list[dict]:
    url = f"{REPORTING_API_BASE}/apps/{package}/{metric_set}:query"
    resp = requests.post(url, json=payload,
                         headers={"Authorization": f"Bearer {token}"}, timeout=30)
    if resp.status_code == 403:
        log.warning("403 Forbidden: %s/%s — check service account permissions",
                    package, metric_set)
        return []
    if resp.status_code == 400:
        log.warning("400 Bad Request: %s/%s — %s", package, metric_set,
                    resp.json().get("error", {}).get("message", ""))
        return []
    resp.raise_for_status()
    rows = resp.json().get("rows", [])
    log.info("  %-40s %3d rows", metric_set, len(rows))
    return rows


def list_anomalies(token: str, package: str) -> list[dict]:
    url = f"{REPORTING_API_BASE}/apps/{package}/anomalies"
    resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=15)
    if resp.status_code in (403, 404):
        return []
    resp.raise_for_status()
    items = resp.json().get("anomalies", [])
    log.info("  %-40s %3d anomalies", "anomalies", len(items))
    return items


# ── OTLP/HTTP JSON export ─────────────────────────────────────────────────────


def _row_time_ns(row: dict) -> str:
    """Extract the row's startTime as a Unix nanosecond string for OTLP JSON."""
    st = row.get("startTime", {})
    if st:
        dt = datetime(st["year"], st["month"], st["day"], 12, 0, 0, tzinfo=timezone.utc)
    else:
        dt = datetime.now(timezone.utc)
    return str(int(dt.timestamp() * 1_000_000_000))


_DIM_KEY_MAP = {
    "reportType": "report_type",
    "startType": "start_type",
    "versionCode": "version_code",
    "apiLevel": "api_level",
    "countryCode": "country_code",
    "deviceType": "device_type",
    "deviceRamBucket": "device_ram_bucket",
    "deviceSocMake": "device_soc_make",
    "deviceSocModel": "device_soc_model",
    "deviceAvailableRam": "device_available_ram",
    "deviceLargeRam": "device_large_ram",
}


def _otlp_attrs(package: str, row: dict) -> list[dict]:
    """Build OTLP attribute list from a row's dimensions."""
    attrs = [
        {"key": "android.package", "value": {"stringValue": package}},
    ]
    # Always include the measurement date so users can filter by specific days in Last9.
    st = row.get("startTime", {})
    if st:
        date_str = f"{st['year']}-{st['month']:02d}-{st['day']:02d}"
        attrs.append({"key": "android.date", "value": {"stringValue": date_str}})
    # The API returns dimensions as [{dimension: "reportType", stringValue: "ANR"}, ...]
    for dim_entry in row.get("dimensions", []):
        api_name = dim_entry.get("dimension", "")
        if not api_name:
            continue
        val = dim_entry.get("stringValue") or str(dim_entry.get("int64Value", ""))
        attr_key = f"android.{_DIM_KEY_MAP.get(api_name, api_name)}"
        attrs.append({"key": attr_key, "value": {"stringValue": val}})
    return attrs


def _metric_value(entry: dict) -> tuple[str, Any]:
    """Return ('asDouble', float) or ('asInt', int) for an OTLP data point."""
    dec = entry.get("decimalValue")
    if dec:
        return "asDouble", float(dec["value"])
    i64 = entry.get("int64Value")
    if i64 is not None:
        return "asInt", str(int(i64))
    return "asDouble", 0.0


def send_otlp_metrics(
    rows_by_set: list[tuple[str, list[dict]]],
    package: str,
) -> None:
    """
    POST all rows to Last9 as OTLP/HTTP JSON gauge data points.

    rows_by_set: list of (metric_set, rows)
    Each row gets its own data point with the row's startTime as the timestamp.
    """
    data_points_by_otel_name: dict[str, tuple[str, str, list[dict]]] = {}

    for metric_set, rows in rows_by_set:
        catalogue = METRIC_CATALOGUE.get(metric_set, {})
        for row in rows:
            time_ns = _row_time_ns(row)
            attrs = _otlp_attrs(package, row)
            for entry in row.get("metrics", []):
                api_name = entry.get("metric")
                if api_name not in catalogue:
                    continue
                otel_name, unit, description = catalogue[api_name]
                val_key, val = _metric_value(entry)
                dp = {"attributes": attrs, "timeUnixNano": time_ns, val_key: val}
                if otel_name not in data_points_by_otel_name:
                    data_points_by_otel_name[otel_name] = (unit, description, [])
                data_points_by_otel_name[otel_name][2].append(dp)

    if not data_points_by_otel_name:
        return

    metrics_payload = [
        {
            "name": otel_name,
            "unit": unit,
            "description": description,
            "gauge": {"dataPoints": dps},
        }
        for otel_name, (unit, description, dps) in data_points_by_otel_name.items()
    ]

    payload = {
        "resourceMetrics": [{
            "resource": {
                "attributes": [
                    {"key": "service.name", "value": {"stringValue": OTEL_SERVICE_NAME}},
                    {"key": "telemetry.sdk.language", "value": {"stringValue": "python"}},
                ]
            },
            "scopeMetrics": [{
                "scope": {"name": "google.play.reporting", "version": "1.0.0"},
                "metrics": metrics_payload,
            }],
        }]
    }

    headers = {**_parse_headers(OTLP_HEADERS_RAW), "Content-Type": "application/json"}
    resp = requests.post(
        f"{OTLP_ENDPOINT.rstrip('/')}/v1/metrics",
        json=payload,
        headers=headers,
        timeout=30,
    )
    if resp.status_code not in (200, 204):
        log.warning("OTLP export failed: HTTP %s — %s", resp.status_code, resp.text[:200])
    else:
        total_dps = sum(len(v[2]) for v in data_points_by_otel_name.values())
        log.info("Exported %d data points (%d metrics) to Last9",
                 total_dps, len(data_points_by_otel_name))


# ── Anomaly log records ───────────────────────────────────────────────────────


def emit_anomalies(anomalies: list[dict], package: str, otel_logger: Any) -> None:
    for a in anomalies:
        metric_name = a.get("metric", "unknown")
        dims = {d.get("dimension"): d.get("stringValue") or str(d.get("int64Value", ""))
                for d in a.get("dimensionValue", [])}
        body = (f"Android vitals anomaly: {metric_name} is outside 28-day baseline"
                + (f" for {dims}" if dims else ""))
        record = otel_logger.create_log_record(
            timestamp=int(datetime.now(timezone.utc).timestamp() * 1e9),
            severity_number=SeverityNumber.WARN,
            severity_text="WARN",
            body=body,
            attributes={
                "android.package": package,
                "android.vitals.anomaly.metric": metric_name,
                "android.vitals.anomaly.name": a.get("name", ""),
                **{f"android.{k}": v for k, v in dims.items()},
            },
        )
        otel_logger.emit(record)


# ── Poll one package ──────────────────────────────────────────────────────────


def poll_package(token: str, package: str, otel_logger: Any) -> None:
    log.info("Polling: %s", package)
    rows_by_set: list[tuple[str, list[dict]]] = []

    # ── Daily metric sets ─────────────────────────────────────────────────────
    for metric_set, metric_names in DAILY_METRIC_NAMES.items():
        extra_dims = DAILY_REQUIRED_EXTRA_DIMS.get(metric_set)
        try:
            freshness = get_freshness(token, package, metric_set)
            end = freshness.get("DAILY", date.today() - timedelta(days=2))
            rows = query_daily(token, package, metric_set, metric_names, end,
                               extra_dims=extra_dims)
            rows_by_set.append((metric_set, rows))
        except requests.HTTPError as exc:
            log.error("HTTP error — %s/%s: %s", package, metric_set, exc)
        except Exception as exc:  # noqa: BLE001
            log.error("Error — %s/%s: %s", package, metric_set, exc)

    # ── Hourly crash/ANR (optional, ~2-4h lag) ────────────────────────────────
    if ENABLE_HOURLY:
        for metric_set, metric_names in HOURLY_METRIC_NAMES.items():
            try:
                freshness = get_freshness(token, package, metric_set)
                end = freshness.get("HOURLY", date.today() - timedelta(days=1))
                rows = query_hourly(token, package, metric_set, metric_names, end)
                rows_by_set.append((metric_set, rows))
            except Exception as exc:  # noqa: BLE001
                log.error("Hourly error — %s/%s: %s", package, metric_set, exc)

    # ── Error counts (hourly, leading indicator) ──────────────────────────────
    error_count_base_dims = [d for d in DIMENSIONS if d not in ERROR_COUNT_UNSUPPORTED_DIMS]
    try:
        freshness = get_freshness(token, package, "errorCountMetricSet")
        end = freshness.get("HOURLY", date.today() - timedelta(days=1))
        rows = query_hourly(
            token, package, "errorCountMetricSet",
            list(METRIC_CATALOGUE["errorCountMetricSet"].keys()), end,
            extra_dims=ERROR_COUNT_EXTRA_DIMS,
            base_dims=error_count_base_dims,
        )
        rows_by_set.append(("errorCountMetricSet", rows))
    except Exception as exc:  # noqa: BLE001
        log.error("Error — %s/errorCountMetricSet: %s", package, exc)

    # ── Export all rows to Last9 ──────────────────────────────────────────────
    send_otlp_metrics(rows_by_set, package)

    # ── Anomalies → OTel log records ──────────────────────────────────────────
    try:
        anomalies = list_anomalies(token, package)
        if anomalies:
            emit_anomalies(anomalies, package, otel_logger)
    except Exception as exc:  # noqa: BLE001
        log.error("Anomaly fetch error — %s: %s", package, exc)


# ── Entry point ───────────────────────────────────────────────────────────────


def main() -> None:
    log.info("Google Play Reporting collector starting")
    log.info("Packages       : %s", PACKAGE_NAMES)
    log.info("Poll interval  : %ds", POLL_INTERVAL_SECONDS)
    log.info("Days back      : %d", POLL_DAYS_BACK)
    log.info("Hourly enabled : %s", ENABLE_HOURLY)
    log.info("Dimensions     : %s", DIMENSIONS or ["(aggregate)"])
    log.info("OTLP endpoint  : %s", OTLP_ENDPOINT)

    creds = load_credentials()

    logger_provider = build_logger_provider()
    set_logger_provider(logger_provider)
    otel_logger = logger_provider.get_logger("google.play.reporting.anomalies")

    def _shutdown(sig, _frame):
        log.info("Shutting down…")
        logger_provider.shutdown()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    while True:
        token = bearer_token(creds)
        for package in PACKAGE_NAMES:
            poll_package(token, package, otel_logger)
        log.info("Sleeping %ds…", POLL_INTERVAL_SECONDS)
        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
