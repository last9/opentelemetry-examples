# Google Play Developer Reporting → Last9

Polls Android vitals (crash rate, ANR rate, slow rendering, slow start) from the
[Google Play Developer Reporting API](https://developers.google.com/play/developer/reporting)
and exports them as OpenTelemetry metrics to Last9.

**Data freshness:** Google processes Android vitals with a 24–48 hour lag. This is
a Google-side constraint, not an integration limitation.

## Prerequisites

- Python 3.13+ or Docker
- Google Play Console service account with **View app information and download bulk reports** permission
- Last9 account with OTLP ingestion enabled

## Google Play Console Setup

1. Go to **Play Console → Setup → API access**
2. Link or create a Google Cloud project
3. Create a service account (or use an existing one)
4. Grant the service account **View app information and download bulk reports (read-only)**
5. Download the JSON key file — store it securely, never commit it

## Quick Start

```bash
cp .env.example .env
# Edit .env with your values

# Set the path to your service account JSON
export SERVICE_ACCOUNT_JSON_PATH=/path/to/your/service-account.json

docker compose up
```

## Configuration

| Variable | Description | Default |
|---|---|---|
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to service account JSON inside container | `/run/secrets/service-account.json` |
| `ANDROID_PACKAGE_NAMES` | Comma-separated package names to monitor | `com.example.app` |
| `POLL_INTERVAL_SECONDS` | Poll frequency (Google data is 24–48hr stale regardless) | `1800` |
| `OTLP_ENDPOINT` | Last9 OTLP endpoint | `https://otlp.last9.io` |
| `OTLP_HEADERS` | Auth headers (`Authorization=Basic <token>`) | — |
| `OTEL_SERVICE_NAME` | Service name in Last9 | `google-play-reporting` |

## Metrics Exported

| Metric | Unit | Description |
|---|---|---|
| `android.vitals.crash_rate` | fraction | Daily crash rate |
| `android.vitals.crash_rate_7d` | fraction | 7-day user-weighted crash rate |
| `android.vitals.user_perceived_crash_rate` | fraction | Foreground crash rate |
| `android.vitals.anr_rate` | fraction | Daily ANR rate |
| `android.vitals.anr_rate_7d` | fraction | 7-day user-weighted ANR rate |
| `android.vitals.user_perceived_anr_rate` | fraction | Foreground ANR rate |
| `android.vitals.slow_rendering_rate_20fps` | fraction | Sessions with <20 FPS rendering |
| `android.vitals.slow_rendering_rate_30fps` | fraction | Sessions with <30 FPS rendering |
| `android.vitals.slow_start_rate` | fraction | Fraction of slow app starts |

All metrics carry `android.package`, `android.versionCode`, and `android.apiLevel` attributes.

## Run without Docker

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
export ANDROID_PACKAGE_NAMES=com.example.app
export OTLP_ENDPOINT=https://otlp.last9.io
export OTLP_HEADERS="Authorization=Basic <your-token>"

python main.py
```

## Verification

After starting the collector, check Last9 for metrics with the prefix `android.vitals.*`.
You can also check the container logs:

```
2026-02-26 10:00:00 INFO Polling package: com.example.app
2026-02-26 10:00:02 INFO Fetched 142 rows from com.example.app / crashRateMetricSet
2026-02-26 10:00:03 INFO Fetched 138 rows from com.example.app / anrRateMetricSet
```
