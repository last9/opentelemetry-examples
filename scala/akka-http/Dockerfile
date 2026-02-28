# Build stage
FROM sbtscala/scala-sbt:eclipse-temurin-17_1.9.9_3.3.4 AS build

WORKDIR /app

# Cache dependencies before copying source
COPY build.sbt .
COPY project/ project/
RUN sbt update

# Build fat JAR
COPY src/ src/
RUN sbt assembly

# Runtime stage
FROM eclipse-temurin:17-jre

WORKDIR /app

# Download the OpenTelemetry Java agent.
# The agent instruments Pekko/Akka HTTP, JDBC, Kafka, and Lettuce (Redis) automatically
# without any changes to application code.
ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.10.0/opentelemetry-javaagent.jar \
    /app/otel-javaagent.jar

COPY --from=build /app/target/scala-3.3.4/akka-http-otel.jar /app/app.jar

# Default OTel environment — can be overridden at runtime
ENV OTEL_SERVICE_NAME=akka-http-service
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
ENV OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_METRICS_EXPORTER=otlp
ENV OTEL_LOGS_EXPORTER=otlp
ENV OTEL_TRACES_SAMPLER=always_on

EXPOSE 8080

ENTRYPOINT ["java", "-javaagent:/app/otel-javaagent.jar", "-jar", "/app/app.jar"]
