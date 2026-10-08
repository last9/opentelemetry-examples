# Custom OpenTelemetry Collector image with RDS CA bundle
# Use this if you need to customize the collector

FROM alpine:3.23 AS certificates
RUN wget -q https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
    -O /rds-combined-ca-bundle.pem

FROM otel/opentelemetry-collector-contrib:0.162.0 AS collector
FROM alpine:3.23
RUN apk add --no-cache ca-certificates
COPY --from=collector /otelcol-contrib /otelcol-contrib
COPY --from=certificates /rds-combined-ca-bundle.pem /etc/ssl/certs/rds-combined-ca-bundle.pem

COPY config/otel-evidence-config.yaml /etc/otel/config.yaml
USER 10001
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD wget --spider -q http://localhost:13133/health || exit 1

EXPOSE 13133 8888 55679

ENTRYPOINT ["/otelcol-contrib"]
CMD ["--config=/etc/otel/config.yaml", "--feature-gates=receiver.postgresql.useOTelSemconv"]
