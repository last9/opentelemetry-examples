# GCP Cloud Run and Cloud Tasks Metrics Collector for Last9

Enterprise-grade metrics collection for GCP Cloud Run and Cloud Tasks services. This solution uses Prometheus and Stackdriver Exporter to reliably collect GCP infrastructure metrics and forward them to Last9 for monitoring and alerting.

## Overview

**What This Collector Does:**
1. Runs as a Cloud Run service in your GCP project
2. Queries Cloud Monitoring API
3. Converts GCP metrics to Prometheus format
4. Forwards metrics to Last9 using Prometheus remote write protocol
5. Adds helpful labels (environment, source, collector type)

**Examples of some of Metrics Collected:**

*Cloud Run (6 metrics):*
- `run_googleapis_com_request_count` - Total HTTP requests
- `run_googleapis_com_request_latencies` - Request latency distribution (p50, p95, p99)
- `run_googleapis_com_container_cpu_utilizations` - CPU usage per instance
- `run_googleapis_com_container_memory_utilizations` - Memory usage per instance
- `run_googleapis_com_container_instance_count` - Number of running instances
- `run_googleapis_com_container_billable_instance_time` - Billable instance time

*Cloud Tasks (2 metrics):*
- `cloudtasks_googleapis_com_queue_depth` - Number of tasks in queue
- `cloudtasks_googleapis_com_task_attempt_count` - Task execution attempts

## Prerequisites

### GCP Requirements
- **GCP Project** with billing enabled
- **Cloud Run or Cloud Tasks** services running (to generate metrics)
- **APIs Enabled**:
  - Cloud Run API (`run.googleapis.com`)
  - Cloud Monitoring API (`monitoring.googleapis.com`)
  - Secret Manager API (`secretmanager.googleapis.com`)
  - Cloud Build API (`cloudbuild.googleapis.com`)

### Last9 Requirements
- **Last9 Account** - Sign up at https://last9.io
- **Prometheus Remote Write URL** - Get from Last9 dashboard:
  1. Log in to Last9
  2. Navigate to **Settings → Integrtion → Prometheus Remote Write**
  3. Copy the **Remote Write URL**
- **Last9 Credentials** - Username and password for basic auth (shown in same section)

### Local Tools
- `gcloud` CLI installed and authenticated (`gcloud auth login`)
- Docker (optional, for local testing only)

## Setup Instructions

### Step 1: Enable Required GCP APIs

```bash
# Set your project ID
export PROJECT_ID=your-gcp-project-id

# Enable required APIs
gcloud services enable \
  run.googleapis.com \
  monitoring.googleapis.com \
  secretmanager.googleapis.com \
  cloudbuild.googleapis.com \
  --project=$PROJECT_ID
```

### Step 2: Create Service Account with Monitoring Permissions

This service account will be used by the collector to query GCP Cloud Monitoring API.

```bash
# Create service account
gcloud iam service-accounts create metrics-collector \
  --display-name="Cloud Run Metrics Collector" \
  --description="Collects GCP Cloud Run metrics and forwards to Last9" \
  --project=$PROJECT_ID

# Grant Cloud Monitoring Viewer role (required to read metrics)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:metrics-collector@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/monitoring.viewer"

# Grant Secret Manager Accessor role (required to read Last9 credentials)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:metrics-collector@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

**Verify service account creation:**
```bash
gcloud iam service-accounts describe \
  metrics-collector@$PROJECT_ID.iam.gserviceaccount.com \
  --project=$PROJECT_ID
```

### Step 3: Store Last9 Credentials in Secret Manager

Get your Last9 credentials from the Last9 dashboard, then store them securely:

```bash
# Store Last9 username (replace with your actual username)
echo -n "your-last9-username" | \
  gcloud secrets create last9-username \
  --data-file=- \
  --project=$PROJECT_ID

# Store Last9 password (replace with your actual password)
echo -n "your-last9-password" | \
  gcloud secrets create last9-password \
  --data-file=- \
  --project=$PROJECT_ID

# Verify secrets were created
gcloud secrets list --project=$PROJECT_ID
```

**Expected output:**
```
NAME             CREATED              REPLICATION_POLICY  LOCATIONS
last9-password   2025-01-07T...       automatic           -
last9-username   2025-01-07T...       automatic           -
```

### Step 4: Build and Deploy the Collector

**Option A: Build and Deploy in One Command** (Recommended)

```bash
# Set your Last9 remote write URL
export REMOTE_WRITE_URL="YOUR_PROMETHEUS_ENDPOINT"

# Set your preferred region
export REGION=asia-south1  # or us-central1, europe-west1, etc.

# Build and deploy
gcloud run deploy cloud-run-prometheus-collector \
  --source . \
  --region=$REGION \
  --service-account=metrics-collector@$PROJECT_ID.iam.gserviceaccount.com \
  --set-env-vars="GCP_PROJECT_ID=$PROJECT_ID,REMOTE_WRITE_URL=$REMOTE_WRITE_URL" \
  --set-secrets="LAST9_USERNAME=last9-username:latest,LAST9_PASSWORD=last9-password:latest" \
  --memory=512Mi \
  --cpu=1 \
  --timeout=300 \
  --concurrency=1 \
  --min-instances=1 \
  --max-instances=1 \
  --no-allow-unauthenticated \
  --port=8080 \
  --project=$PROJECT_ID
```

**Option B: Build with Cloud Build, Then Deploy**

```bash
# Build Docker image
gcloud builds submit \
  --tag gcr.io/$PROJECT_ID/cloud-run-prometheus-collector:v1 \
  --project=$PROJECT_ID

# Deploy to Cloud Run
gcloud run deploy cloud-run-prometheus-collector \
  --image gcr.io/$PROJECT_ID/cloud-run-prometheus-collector:v1 \
  --region=$REGION \
  --service-account=metrics-collector@$PROJECT_ID.iam.gserviceaccount.com \
  --set-env-vars="GCP_PROJECT_ID=$PROJECT_ID,REMOTE_WRITE_URL=$REMOTE_WRITE_URL" \
  --set-secrets="LAST9_USERNAME=last9-username:latest,LAST9_PASSWORD=last9-password:latest" \
  --memory=512Mi \
  --cpu=1 \
  --timeout=300 \
  --concurrency=1 \
  --min-instances=1 \
  --max-instances=1 \
  --no-allow-unauthenticated \
  --port=8080 \
  --project=$PROJECT_ID
```

**Deployment Configuration Explained:**
- `--memory=512Mi` - Sufficient for buffering metrics
- `--cpu=1` - One CPU core is enough for scraping and forwarding
- `--timeout=300` - 5-minute timeout to match scrape interval
- `--concurrency=1` - Single request at a time (avoid parallel scrapes)
- `--min-instances=1 --max-instances=1` - Always-on, prevents cold starts
- `--no-allow-unauthenticated` - Requires authentication to access the service
- `--port=8080` - Prometheus UI port

### Step 5: Verify Deployment

**Check service status:**
```bash
gcloud run services describe cloud-run-prometheus-collector \
  --region=$REGION \
  --project=$PROJECT_ID \
  --format="value(status.url)"
```

**View logs:**
```bash
gcloud run services logs read cloud-run-prometheus-collector \
  --region=$REGION \
  --project=$PROJECT_ID \
  --limit=50
```

### Step 6: Generate Traffic (For Testing)

To verify metrics are being collected, generate some Cloud Run and Task traffic.

Wait sometime, then check Last9 dashboard for incoming metrics.

### Step 7: Verify Metrics in Last9

1. Log in to Last9 dashboard
2. Navigate to **Explore → Metrics**
3. Search for metrics with `_run_googleapis_com_`


## Support

For issues or questions:

1. **Check logs first:**
   ```bash
   gcloud run services logs read cloud-run-prometheus-collector \
     --region=$REGION \
     --project=$PROJECT_ID \
     --limit=100
   ```

2. **Contact Last9 support:** support@last9.io

3. **GCP documentation:**
   - [Cloud Run](https://cloud.google.com/run/docs)
   - [Cloud Monitoring API](https://cloud.google.com/monitoring/api)
   - [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)