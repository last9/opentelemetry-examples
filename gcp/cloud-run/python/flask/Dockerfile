# Multi-stage build for smaller image size
FROM python:3.11-slim as builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Production stage
FROM python:3.11-slim

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /root/.local /root/.local
ENV PATH=/root/.local/bin:$PATH

# Copy application code
COPY app.py .

# Cloud Run expects the app to listen on PORT environment variable
ENV PORT=8080
EXPOSE 8080

# Use gunicorn for production with appropriate settings for Cloud Run
# - Workers: 1 (Cloud Run handles scaling via instances)
# - Threads: 4 (handle concurrent requests within instance)
# - Timeout: 0 (let Cloud Run handle request timeouts)
# - Graceful timeout: 30s (for clean shutdown)
CMD ["gunicorn", \
     "--bind", "0.0.0.0:8080", \
     "--workers", "1", \
     "--threads", "4", \
     "--timeout", "0", \
     "--graceful-timeout", "30", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "--capture-output", \
     "app:app"]
