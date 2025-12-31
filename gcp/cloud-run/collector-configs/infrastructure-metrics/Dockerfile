# Use official OTEL Collector Contrib (includes googlecloudmonitoring receiver)
# Version 0.112.0+ required for googlecloudmonitoring receiver
FROM otel/opentelemetry-collector-contrib:0.115.1

# Copy configuration
COPY collector-config.yaml /etc/otelcol-contrib/config.yaml

# Expose ports
# 8080: Health check endpoint (required by Cloud Run)
# 8888: Prometheus metrics (collector's own metrics)
EXPOSE 8080 8888

# Health check for Cloud Run
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run collector
CMD ["--config=/etc/otelcol-contrib/config.yaml"]
