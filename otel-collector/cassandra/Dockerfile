FROM otel/opentelemetry-collector-contrib:0.144.0 AS otelcol

# Alpine base: Debian 12's ca-certificates still trusts the roots behind the
# compromised eMudhra intermediates, and the distroless otelcol base lacks a
# shell and the libraries the JRE needs. Alpine's own OpenJDK package covers
# amd64 and arm64 (eclipse-temurin:17-jre-alpine is amd64-only), and its
# cacerts is generated from the system CA bundle upgraded here.
FROM alpine:3.22

# --upgrade pulls the CA bundle newer than the base image ships
RUN apk add --no-cache --upgrade ca-certificates ca-certificates-bundle openjdk17-jre-headless

COPY --from=otelcol /otelcol-contrib /otelcol-contrib

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

USER nobody
ENTRYPOINT ["/otelcol-contrib"]
