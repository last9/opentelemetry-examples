# Build stage
FROM maven:3.9-eclipse-temurin-11 AS build

WORKDIR /app

# Copy auto-configure JAR and install to local Maven repo
COPY vertx3-rxjava2-otel-autoconfigure-1.0.0.jar /tmp/
RUN mvn install:install-file \
    -Dfile=/tmp/vertx3-rxjava2-otel-autoconfigure-1.0.0.jar \
    -DgroupId=io.last9 \
    -DartifactId=vertx3-rxjava2-otel-autoconfigure \
    -Dversion=1.0.0 \
    -Dpackaging=jar

# Copy POM and download dependencies
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source and build
COPY src ./src
RUN mvn package -DskipTests

# Runtime stage
FROM eclipse-temurin:11-jre

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

# Run with verticle argument
ENTRYPOINT ["java", "-jar", "app.jar", "run"]
CMD ["com.example.holding.MainVerticle"]
