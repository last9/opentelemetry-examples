# Custom OpenTelemetry Collector image with RDS CA bundle
# Use this if you need to customize the collector

FROM otel/opentelemetry-collector-contrib:0.91.0

# Download RDS CA bundle for TLS connections
USER root
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates wget \
    && wget -q https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
       -O /etc/ssl/certs/rds-combined-ca-bundle.pem \
    && chmod 644 /etc/ssl/certs/rds-combined-ca-bundle.pem \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy custom config (optional - can be mounted instead)
# COPY config/otel-collector-config.yaml /etc/otel/config.yaml

USER otelcol

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget --spider -q http://localhost:13133/health || exit 1

EXPOSE 13133 8888 55679

ENTRYPOINT ["/otelcol-contrib"]
CMD ["--config=/etc/otel/config.yaml"]
