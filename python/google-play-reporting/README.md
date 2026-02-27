# Google Play Developer Reporting → Last9

Polls all Android vitals metric sets from the
[Google Play Developer Reporting API](https://developers.google.com/play/developer/reporting)
and exports them as OpenTelemetry metrics (+ anomaly log events) to Last9.

**Data freshness:** Daily metrics lag 24–48 hours; hourly error counts lag ~2–4 hours.
Both are Google-side constraints, not integration limitations.

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
| `POLL_INTERVAL_SECONDS` | Poll frequency in seconds | `1800` |
| `POLL_DAYS_BACK` | Days of history to fetch each poll | `30` |
| `ENABLE_HOURLY` | Also poll crash/ANR at hourly granularity (~2–4h lag) | `false` |
| `ANDROID_DIMENSIONS` | Comma-separated dimensions (e.g. `versionCode,apiLevel`) | _(aggregate)_ |
| `OTLP_ENDPOINT` | Last9 OTLP endpoint | `https://otlp.last9.io` |
| `OTLP_HEADERS` | Auth headers (`Authorization=Basic <token>`) | — |
| `OTEL_SERVICE_NAME` | Service name shown in Last9 | `google-play-reporting` |

> **Dimension note:** Google may return empty rows for per-dimension queries on low-traffic apps.
> Start with `ANDROID_DIMENSIONS=` (empty) and only enable dimensions once you confirm aggregate data flows.

## Metrics Exported

### Crash rate (`crashRateMetricSet`)
| Metric | Description |
|---|---|
| `android.vitals.crash_rate` | Daily crash rate |
| `android.vitals.crash_rate_7d` | 7-day user-weighted crash rate |
| `android.vitals.crash_rate_28d` | 28-day user-weighted crash rate |
| `android.vitals.user_perceived_crash_rate` | Foreground crash rate |
| `android.vitals.user_perceived_crash_rate_7d` | 7-day user-perceived crash rate |
| `android.vitals.user_perceived_crash_rate_28d` | 28-day user-perceived crash rate |

### ANR rate (`anrRateMetricSet`)
| Metric | Description |
|---|---|
| `android.vitals.anr_rate` | Daily ANR rate |
| `android.vitals.anr_rate_7d` | 7-day user-weighted ANR rate |
| `android.vitals.anr_rate_28d` | 28-day user-weighted ANR rate |
| `android.vitals.user_perceived_anr_rate` | Foreground ANR rate |
| `android.vitals.user_perceived_anr_rate_7d` | 7-day user-perceived ANR rate |
| `android.vitals.user_perceived_anr_rate_28d` | 28-day user-perceived ANR rate |

### Slow rendering (`slowRenderingRateMetricSet`)
| Metric | Description |
|---|---|
| `android.vitals.slow_rendering_rate_20fps` | Sessions rendering below 20 FPS |
| `android.vitals.slow_rendering_rate_20fps_7d` | 7-day slow rendering <20 FPS |
| `android.vitals.slow_rendering_rate_30fps` | Sessions rendering below 30 FPS |
| `android.vitals.slow_rendering_rate_30fps_7d` | 7-day slow rendering <30 FPS |

### Slow start (`slowStartRateMetricSet`)
Broken down by `android.startType` dimension (COLD / WARM / HOT).

| Metric | Description |
|---|---|
| `android.vitals.slow_start_rate` | Fraction of slow app starts |
| `android.vitals.slow_start_rate_7d` | 7-day slow start rate |
| `android.vitals.slow_start_rate_28d` | 28-day slow start rate |

### Excessive wakeup (`excessiveWakeupRateMetricSet`)
| Metric | Description |
|---|---|
| `android.vitals.excessive_wakeup_rate` | Sessions with >10 AlarmManager wakeups/hour |
| `android.vitals.excessive_wakeup_rate_7d` | 7-day excessive wakeup rate |
| `android.vitals.excessive_wakeup_rate_28d` | 28-day excessive wakeup rate |

### Stuck background wakelock (`stuckBackgroundWakelockRateMetricSet`)
| Metric | Description |
|---|---|
| `android.vitals.stuck_background_wakelock_rate` | Sessions with wakelock held >1 hour in background |
| `android.vitals.stuck_background_wakelock_rate_7d` | 7-day stuck wakelock rate |
| `android.vitals.stuck_background_wakelock_rate_28d` | 28-day stuck wakelock rate |

### Low Memory Kill (`lmkRateMetricSet`)
| Metric | Description |
|---|---|
| `android.vitals.lmk_rate` | App killed by Android OOM killer during active use |
| `android.vitals.lmk_rate_7d` | 7-day LMK rate |
| `android.vitals.lmk_rate_28d` | 28-day LMK rate |

### Error counts (`errorCountMetricSet`, hourly)
Broken down by `android.reportType` dimension (CRASH / ANR).

| Metric | Description |
|---|---|
| `android.vitals.error_report_count` | Hourly error report count (leading indicator, ~2–4h lag) |
| `android.vitals.error_distinct_users` | Distinct users with errors |

### Anomalies
Google-detected anomalies (metric deviates from 28-day baseline) are exported as
**OTel WARN log records** with attributes:
- `android.package`
- `android.vitals.anomaly.metric`
- Any dimension values (e.g. `android.versionCode`)

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

After starting, check Last9 for metrics with prefix `android.vitals.*`.
Container logs show polling progress:

```
2026-02-26 10:00:00 INFO Google Play Reporting collector starting
2026-02-26 10:00:00 INFO Packages       : ['com.example.app']
2026-02-26 10:00:01 INFO Polling: com.example.app
2026-02-26 10:00:03 INFO   crashRateMetricSet                        142 rows
2026-02-26 10:00:04 INFO   anrRateMetricSet                          138 rows
2026-02-26 10:00:05 INFO   errorCountMetricSet                        96 rows
```
