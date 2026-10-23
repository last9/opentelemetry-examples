# azuremonitorreceiver is in the contrib distribution.
# Pinned: 0.163.2+ ships Go and CA bundle updates that distrust the compromised eMudhra intermediates
FROM otel/opentelemetry-collector-contrib:0.163.2

COPY collector-config.yaml /etc/otelcol-contrib/config.yaml

EXPOSE 13133

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:13133/ || exit 1

CMD ["--config=/etc/otelcol-contrib/config.yaml"]
