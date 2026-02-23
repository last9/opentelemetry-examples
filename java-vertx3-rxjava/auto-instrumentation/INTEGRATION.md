# Vert.x 3 RxJava2 OpenTelemetry Integration

Auto-instrument your Vert.x 3 application with zero-code tracing.

## Installation

Download the JAR and install to your local Maven repository:

```bash
curl -LO https://github.com/last9/vertx-opentelemetry/releases/download/v1.0.0/vertx3-rxjava2-otel-autoconfigure-1.0.0.jar

mvn install:install-file -Dfile=vertx3-rxjava2-otel-autoconfigure-1.0.0.jar \
  -DgroupId=io.last9 -DartifactId=vertx3-rxjava2-otel-autoconfigure -Dversion=1.0.0 -Dpackaging=jar
```

## Maven Dependency

Add to your `pom.xml`:

```xml
<dependency>
    <groupId>io.last9</groupId>
    <artifactId>vertx3-rxjava2-otel-autoconfigure</artifactId>
    <version>1.0.0</version>
</dependency>
```

## Code Changes

### 1. Use TracedRouter

Replace `Router.router(vertx)` with `TracedRouter.create(vertx)`:

```java
import io.last9.tracing.otel.v3.TracedRouter;

// Before
Router router = Router.router(vertx);

// After
Router router = TracedRouter.create(vertx);
```

### 2. Configure Main Class

Update `pom.xml` maven-shade-plugin to use `OtelLauncher`:

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-shade-plugin</artifactId>
    <version>3.5.1</version>
    <executions>
        <execution>
            <phase>package</phase>
            <goals><goal>shade</goal></goals>
            <configuration>
                <transformers>
                    <transformer implementation="org.apache.maven.plugins.shade.resource.ManifestResourceTransformer">
                        <mainClass>io.last9.tracing.otel.v3.OtelLauncher</mainClass>
                        <manifestEntries>
                            <Main-Verticle>com.yourpackage.MainVerticle</Main-Verticle>
                        </manifestEntries>
                    </transformer>
                    <transformer implementation="org.apache.maven.plugins.shade.resource.ServicesResourceTransformer"/>
                </transformers>
            </configuration>
        </execution>
    </executions>
</plugin>
```

### 3. Configure Logback

Create/update `src/main/resources/logback.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <turboFilter class="io.last9.tracing.otel.MdcTraceTurboFilter"/>

    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{36} trace_id=%X{trace_id} span_id=%X{span_id} - %msg%n</pattern>
        </encoder>
    </appender>

    <appender name="OTEL" class="io.opentelemetry.instrumentation.logback.appender.v1_0.OpenTelemetryAppender">
        <captureExperimentalAttributes>true</captureExperimentalAttributes>
        <captureCodeAttributes>true</captureCodeAttributes>
        <captureMdcAttributes>*</captureMdcAttributes>
    </appender>

    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
        <appender-ref ref="OTEL"/>
    </root>
</configuration>
```

## Environment Variables

```bash
# Required
OTEL_SERVICE_NAME=your-service-name
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.last9.io:443
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic <your-token>"

# Optional
OTEL_RESOURCE_ATTRIBUTES="deployment.environment=production"
OTEL_LOGS_EXPORTER=otlp
```

## Run

```bash
mvn clean package
java -jar target/your-app.jar run com.yourpackage.MainVerticle
```

## What Gets Traced

- HTTP server requests (method, route, status code)
- HTTP client calls (downstream services)
- RxJava2 context propagation
- Log correlation (trace_id, span_id in logs)
