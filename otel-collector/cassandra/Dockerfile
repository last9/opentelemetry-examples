FROM eclipse-temurin:17-jre-jammy AS java
FROM otel/opentelemetry-collector-contrib:0.144.0 AS otelcol

# Use a Debian slim base so the Temurin JRE (Ubuntu glibc) links correctly.
# The distroless otelcol base lacks some runtime libraries the JRE needs.
FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=otelcol /otelcol-contrib /otelcol-contrib
COPY --from=java /opt/java/openjdk /opt/java/openjdk

ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

USER nobody
ENTRYPOINT ["/otelcol-contrib"]
