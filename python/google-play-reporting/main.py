"""
Google Play Developer Reporting API → OpenTelemetry Metrics Pipeline

Polls Android vitals (crash rate, ANR rate, slow rendering, slow start) from
the Play Developer Reporting API and exports them as OTel gauge metrics via OTLP.

Data freshness: Google processes data with a 24–48hr lag. Poll interval default
is 30 minutes — increasing this does not improve freshness.

Credentials: Set GOOGLE_APPLICATION_CREDENTIALS to the path of your service account
JSON file. The file is never baked into the container image; mount it at runtime.
"""

import os
import time
import logging
import requests

from datetime import date, timedelta
from google.auth.transport.requests import Request
from google.oauth2 import service_account

from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

# ── Configuration ─────────────────────────────────────────────────────────────

GOOGLE_APPLICATION_CREDENTIALS = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
PACKAGE_NAMES = [
    p.strip()
    for p in os.environ.get("ANDROID_PACKAGE_NAMES", "com.example.app").split(",")
    if p.strip()
]
POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL_SECONDS", "1800"))
# How many days back to query. Google requires data to exist for a date range;
# sparse apps (< ~500 DAU) may only have data for a few dates per month.
POLL_DAYS_BACK = int(os.environ.get("POLL_DAYS_BACK", "30"))

OTLP_ENDPOINT = os.environ.get("OTLP_ENDPOINT", "https://otlp.last9.io")
OTLP_HEADERS = os.environ.get("OTLP_HEADERS", "")
OTEL_SERVICE_NAME = os.environ.get("OTEL_SERVICE_NAME", "google-play-reporting")

REPORTING_API_BASE = "https://playdeveloperreporting.googleapis.com/v1beta1"
SCOPES = ["https://www.googleapis.com/auth/playdeveloperreporting"]

# Dimensions to break metrics down by. Leave empty for aggregate totals.
# Google withholds dimension-broken data when an app has fewer than ~500 DAU.
# Set ANDROID_DIMENSIONS=versionCode,apiLevel once you have sufficient user volume.
_raw_dims = os.environ.get("ANDROID_DIMENSIONS", "")
DIMENSIONS = [d.strip() for d in _raw_dims.split(",") if d.strip()]

# ── OTel setup ────────────────────────────────────────────────────────────────


def _parse_otlp_headers(raw: str) -> dict:
    """Parse 'k=v,k2=v2' style header string into a dict."""
    if not raw:
        return {}
    headers = {}
    for pair in raw.split(","):
        if "=" in pair:
            k, v = pair.split("=", 1)
            headers[k.strip()] = v.strip()
    return headers


def build_meter_provider() -> MeterProvider:
    resource = Resource.create({"service.name": OTEL_SERVICE_NAME})
    exporter = OTLPMetricExporter(
        endpoint=f"{OTLP_ENDPOINT.rstrip('/')}/v1/metrics",
        headers=_parse_otlp_headers(OTLP_HEADERS),
    )
    reader = PeriodicExportingMetricReader(exporter, export_interval_millis=60_000)
    return MeterProvider(resource=resource, metric_readers=[reader])


# ── Google auth ───────────────────────────────────────────────────────────────


def get_credentials() -> service_account.Credentials:
    if not GOOGLE_APPLICATION_CREDENTIALS:
        raise RuntimeError(
            "GOOGLE_APPLICATION_CREDENTIALS env var is not set. "
            "Point it to the service account JSON file path."
        )
    return service_account.Credentials.from_service_account_file(
        GOOGLE_APPLICATION_CREDENTIALS,
        scopes=SCOPES,
    )


def refresh_token(creds: service_account.Credentials) -> str:
    if not creds.valid:
        creds.refresh(Request())
    return creds.token


# ── API helpers ───────────────────────────────────────────────────────────────


def _api_date(d: date) -> dict:
    return {"year": d.year, "month": d.month, "day": d.day}


def get_latest_date(token: str, package: str, metric_set: str) -> date:
    """Return the most recent date for which daily data is available."""
    url = f"{REPORTING_API_BASE}/apps/{package}/{metric_set}"
    resp = requests.get(
        url,
        headers={"Authorization": f"Bearer {token}"},
        timeout=15,
    )
    resp.raise_for_status()
    freshnesses = resp.json().get("freshnessInfo", {}).get("freshnesses", [])
    for f in freshnesses:
        if f.get("aggregationPeriod") == "DAILY":
            t = f["latestEndTime"]
            return date(t["year"], t["month"], t["day"])
    return date.today() - timedelta(days=2)


def query_metric_set(
    token: str,
    package: str,
    metric_set: str,
    metric_names: list[str],
    end_date: date,
) -> list[dict]:
    """
    Query a Play Developer Reporting metric set.
    Returns rows with dimensionValues[] and metrics[{metric, decimalValue}].
    """
    start_date = end_date - timedelta(days=POLL_DAYS_BACK - 1)
    url = f"{REPORTING_API_BASE}/apps/{package}/{metric_set}:query"
    payload = {
        "timelineSpec": {
            "aggregationPeriod": "DAILY",
            "startTime": _api_date(start_date),
            "endTime": _api_date(end_date),
        },
        "dimensions": DIMENSIONS,
        "metrics": metric_names,
        "pageSize": 1000,
    }
    resp = requests.post(
        url,
        json=payload,
        headers={"Authorization": f"Bearer {token}"},
        timeout=30,
    )
    if resp.status_code == 403:
        log.error(
            "403 Forbidden for %s/%s — check the service account has "
            "'View app information and download bulk reports' in Play Console → Setup → API access",
            package,
            metric_set,
        )
        return []
    resp.raise_for_status()
    rows = resp.json().get("rows", [])
    log.info("  %s: %d rows", metric_set, len(rows))
    return rows


# ── Metric recording ──────────────────────────────────────────────────────────


def _row_attrs(row: dict, package: str) -> dict:
    """Build OTel attribute dict from a row's dimensionValues."""
    attrs = {"android.package": package}
    dim_vals = row.get("dimensionValues", [])
    for i, dim_name in enumerate(DIMENSIONS):
        if i < len(dim_vals):
            v = dim_vals[i]
            val = v.get("stringValue") or str(v.get("int64Value", ""))
            attrs[f"android.{dim_name}"] = val
    return attrs


def _metric_float(metric_entry: dict) -> float:
    """Extract float value from a metric entry (decimalValue or int64Value)."""
    dec = metric_entry.get("decimalValue")
    if dec:
        return float(dec.get("value", 0))
    return float(metric_entry.get("int64Value", 0))


def record_rows(rows: list[dict], gauges: dict, package: str) -> None:
    """
    Write the latest observation for each (package, dimension-combo) into gauges.

    Each row contains metrics[] where each entry has a 'metric' name field.
    We look up the matching gauge by name rather than relying on array position.
    """
    for row in rows:
        attrs = _row_attrs(row, package)
        for metric_entry in row.get("metrics", []):
            name = metric_entry.get("metric")
            if name and name in gauges:
                gauges[name].set(_metric_float(metric_entry), attrs)


# ── Poll loop ─────────────────────────────────────────────────────────────────


def poll_once(creds: service_account.Credentials, gauges_by_set: dict) -> None:
    token = refresh_token(creds)
    for package in PACKAGE_NAMES:
        log.info("Polling package: %s", package)
        for metric_set, (metric_names, gauges) in gauges_by_set.items():
            try:
                end_date = get_latest_date(token, package, metric_set)
                rows = query_metric_set(token, package, metric_set, metric_names, end_date)
                record_rows(rows, gauges, package)
            except requests.HTTPError as exc:
                log.error("HTTP error — %s/%s: %s", package, metric_set, exc)
            except Exception as exc:  # noqa: BLE001
                log.error("Unexpected error — %s/%s: %s", package, metric_set, exc)


def main() -> None:
    log.info("Starting Google Play Reporting collector")
    log.info("Packages: %s", PACKAGE_NAMES)
    log.info("Poll interval: %ds", POLL_INTERVAL_SECONDS)
    log.info("OTLP endpoint: %s", OTLP_ENDPOINT)

    creds = get_credentials()

    provider = build_meter_provider()
    metrics.set_meter_provider(provider)
    meter = metrics.get_meter("google.play.reporting", version="1.0.0")

    def gauge(name: str, unit: str, description: str):
        return meter.create_gauge(name, unit=unit, description=description)

    # Each entry: metric_set_name → (api_metric_names[], {api_name: OTel gauge})
    gauges_by_set: dict[str, tuple[list, dict]] = {
        "crashRateMetricSet": (
            ["crashRate", "crashRate7dUserWeighted", "userPerceivedCrashRate", "distinctUsers"],
            {
                "crashRate": gauge(
                    "android.vitals.crash_rate", "1",
                    "Daily crash rate (fraction of sessions with a crash)",
                ),
                "crashRate7dUserWeighted": gauge(
                    "android.vitals.crash_rate_7d", "1",
                    "7-day user-weighted crash rate",
                ),
                "userPerceivedCrashRate": gauge(
                    "android.vitals.user_perceived_crash_rate", "1",
                    "Foreground crash rate as perceived by users",
                ),
                "distinctUsers": gauge(
                    "android.vitals.crash_distinct_users", "1",
                    "Distinct users counted in the crash rate denominator",
                ),
            },
        ),
        "anrRateMetricSet": (
            ["anrRate", "anrRate7dUserWeighted", "userPerceivedAnrRate", "distinctUsers"],
            {
                "anrRate": gauge(
                    "android.vitals.anr_rate", "1",
                    "Daily ANR rate",
                ),
                "anrRate7dUserWeighted": gauge(
                    "android.vitals.anr_rate_7d", "1",
                    "7-day user-weighted ANR rate",
                ),
                "userPerceivedAnrRate": gauge(
                    "android.vitals.user_perceived_anr_rate", "1",
                    "Foreground ANR rate as perceived by users",
                ),
                "distinctUsers": gauge(
                    "android.vitals.anr_distinct_users", "1",
                    "Distinct users counted in the ANR rate denominator",
                ),
            },
        ),
        "slowRenderingRateMetricSet": (
            ["slowRenderingRate20Fps", "slowRenderingRate30Fps", "distinctUsers"],
            {
                "slowRenderingRate20Fps": gauge(
                    "android.vitals.slow_rendering_rate_20fps", "1",
                    "Fraction of sessions with slow rendering (below 20 FPS)",
                ),
                "slowRenderingRate30Fps": gauge(
                    "android.vitals.slow_rendering_rate_30fps", "1",
                    "Fraction of sessions with slow rendering (below 30 FPS)",
                ),
                "distinctUsers": gauge(
                    "android.vitals.slow_rendering_distinct_users", "1",
                    "Distinct users in slow rendering denominator",
                ),
            },
        ),
        "slowStartRateMetricSet": (
            ["slowStartRate", "distinctUsers"],
            {
                "slowStartRate": gauge(
                    "android.vitals.slow_start_rate", "1",
                    "Fraction of app starts that are slow",
                ),
                "distinctUsers": gauge(
                    "android.vitals.slow_start_distinct_users", "1",
                    "Distinct users in slow start denominator",
                ),
            },
        ),
    }

    while True:
        poll_once(creds, gauges_by_set)
        log.info("Sleeping %ds until next poll…", POLL_INTERVAL_SECONDS)
        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
