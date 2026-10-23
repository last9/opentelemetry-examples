FROM eclipse-temurin:17-jre-alpine AS java
FROM otel/opentelemetry-collector-contrib:0.144.0 AS otelcol

# Alpine base with the musl Temurin JRE: Debian 12's ca-certificates still
# trusts the roots behind the compromised eMudhra intermediates, and the
# distroless otelcol base lacks a shell and the libraries the JRE needs.
FROM alpine:3.22

# --upgrade pulls the CA bundle newer than the base image ships
RUN apk add --no-cache --upgrade ca-certificates ca-certificates-bundle

COPY --from=otelcol /otelcol-contrib /otelcol-contrib
COPY --from=java /opt/java/openjdk /opt/java/openjdk

ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

USER nobody
ENTRYPOINT ["/otelcol-contrib"]
