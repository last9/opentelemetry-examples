# Build stage
FROM maven:3.9-eclipse-temurin-11 AS build

WORKDIR /app

# Install Last9 auto-configure JARs into local Maven repo.
COPY lib/ /tmp/lib/
RUN mvn install:install-file \
    -Dfile=/tmp/lib/vertx-otel-core.jar \
    -DgroupId=io.last9 \
    -DartifactId=vertx-otel-core \
    -Dversion=2.1.0-beta.1 \
    -Dpackaging=jar \
    -DgeneratePom=true && \
    mvn install:install-file \
    -Dfile=/tmp/lib/vertx3-rxjava2-otel-autoconfigure.jar \
    -DgroupId=io.last9 \
    -DartifactId=vertx3-rxjava2-otel-autoconfigure \
    -Dversion=2.1.0-beta.1 \
    -Dpackaging=jar \
    -DgeneratePom=true

# Copy POM and download dependencies
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source and build
COPY src ./src
RUN mvn package -DskipTests

# Runtime stage
FROM eclipse-temurin:11-jdk

WORKDIR /app

# Copy built JAR
COPY --from=build /app/target/vertx3-rxjava2-otel-example-1.0.0.jar app.jar

# Default environment variables
ENV APP_PORT=8080
ENV OTEL_SERVICE_NAME=vertx3-service
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
ENV OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_LOGS_EXPORTER=otlp

# OtelLauncher handles everything: OTel SDK + ByteBuddy auto-instrumentation
ENTRYPOINT ["java", "-jar", "app.jar", "run"]
CMD ["com.example.holding.MainVerticle"]
