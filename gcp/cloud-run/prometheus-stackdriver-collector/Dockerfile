# Multi-stage build for Prometheus + Stackdriver Exporter
# This image collects GCP Cloud Run and Cloud Jobs metrics and sends them to Last9

FROM golang:1.22-alpine AS stackdriver-builder

# Install dependencies
RUN apk add --no-cache git make

# Build stackdriver_exporter from source
WORKDIR /build
RUN git clone --depth 1 --branch v0.16.0 https://github.com/prometheus-community/stackdriver_exporter.git
WORKDIR /build/stackdriver_exporter
RUN go build -o stackdriver_exporter

# Main image
FROM prom/prometheus:v3.0.1

# Switch to root to install files
USER root

# Copy stackdriver_exporter binary
COPY --from=stackdriver-builder /build/stackdriver_exporter/stackdriver_exporter /usr/local/bin/

# Copy configuration files (template only, entrypoint.sh creates actual config)
COPY prometheus.yml /etc/prometheus/prometheus.yml.template
COPY entrypoint.sh /entrypoint.sh

# Make entrypoint executable
RUN chmod +x /entrypoint.sh && chmod +x /usr/local/bin/stackdriver_exporter

# Create directory for prometheus data with proper permissions
RUN mkdir -p /prometheus && chown -R nobody:nobody /prometheus /etc/prometheus

# Expose ports
# 8080: Prometheus (Cloud Run health check + metrics)
# 9255: Stackdriver Exporter metrics endpoint
EXPOSE 8080 9255

# Health check for Cloud Run
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/-/healthy || exit 1

# Use custom entrypoint to run both services
# Override the Prometheus ENTRYPOINT
ENTRYPOINT []
CMD ["/bin/sh", "/entrypoint.sh"]
