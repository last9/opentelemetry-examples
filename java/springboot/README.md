# Spring Boot OpenTelemetry Demo

A Spring Boot application with OpenTelemetry instrumentation that demonstrates automatic tracing, metrics, and logging collection using the OpenTelemetry Java agent.

## Features

- **Automatic Instrumentation**: Uses OpenTelemetry Java agent for automatic instrumentation
- **Multiple Endpoints**: Various REST endpoints for testing different scenarios
- **Custom Spans**: Manual span creation for business logic
- **Metrics**: Built-in Spring Boot metrics with Prometheus export
- **Logging**: Structured logging with correlation IDs
- **Test Script**: Automated testing script to generate telemetry data
- **Configurable**: All OpenTelemetry settings configurable via environment variables
- **Simplified Infrastructure**: Single OpenTelemetry collector handles all telemetry

## Prerequisites

- Java 17 or higher
- Maven 3.6 or higher
- curl (for test script)
- Docker (optional, for local collector)

## Quick Start

### 1. Clone and Setup

```bash
# Make scripts executable
chmod +x start_app.sh test_script.sh quick_start.sh
```

### 2. Start the Application

```bash
# Start with default settings (logs to console)
./start_app.sh
```

### 3. Run the Test Script

In another terminal:

```bash
./test_script.sh
```

## OpenTelemetry Configuration

The application uses environment variables to configure OpenTelemetry. Here are the key variables you can set:

### Basic Configuration

```bash
# Service name
export OTEL_SERVICE_NAME="springboot-otel-demo"

# Resource attributes
export OTEL_RESOURCE_ATTRIBUTES="service.name=springboot-otel-demo,service.version=1.0.0,deployment.environment=production"
```

### Traces Configuration

```bash
# OTLP exporter (for traces, metrics, logs)
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:14317"
export OTEL_TRACES_EXPORTER="otlp"

# Console exporter (for debugging)
export OTEL_TRACES_EXPORTER="logging"
```

### Metrics Configuration

```bash
# OTLP metrics
export OTEL_METRICS_EXPORTER="otlp"

# Prometheus metrics (exposed on /actuator/prometheus)
export OTEL_METRICS_EXPORTER="prometheus"

# Console metrics
export OTEL_METRICS_EXPORTER="logging"
```

### Logs Configuration

```bash
# OTLP logs
export OTEL_LOGS_EXPORTER="otlp"

# Console logs
export OTEL_LOGS_EXPORTER="logging"
```

### Complete Example

```bash
# Set all environment variables
export OTEL_SERVICE_NAME="springboot-otel-demo"
export OTEL_RESOURCE_ATTRIBUTES="service.name=springboot-otel-demo,service.version=1.0.0,deployment.environment=development"
export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:14317"
export OTEL_TRACES_EXPORTER="otlp"
export OTEL_METRICS_EXPORTER="otlp"
export OTEL_LOGS_EXPORTER="otlp"

# Start the application
./start_app.sh
```

## Local OpenTelemetry Infrastructure

If you want to run a local OpenTelemetry collector for testing:

```bash
# Start the collector
docker compose up -d

# The collector will be available on:
# - OTLP gRPC: localhost:14317
# - OTLP HTTP: localhost:14318
# - Prometheus metrics: localhost:18888
# - Prometheus exporter: localhost:18889
# - Prometheus receiver: localhost:19464
```

## Application Endpoints

The application provides the following endpoints for testing:

### REST API Endpoints

- `GET /api/hello` - Simple hello world endpoint
- `GET /api/health` - Health check endpoint
- `GET /api/users/{id}` - Get user by ID
- `POST /api/users` - Create a new user
- `GET /api/products` - Get products list
- `GET /api/error-demo` - Endpoint that generates errors (for testing error handling)

### Actuator Endpoints

- `GET /actuator/health` - Application health status
- `GET /actuator/metrics` - Available metrics
- `GET /actuator/prometheus` - Prometheus format metrics

## Test Script

The `test_script.sh` script will:

1. Check if the application is running
2. Run 10 test cycles
3. Test all endpoints with different parameters
4. Generate both successful and error scenarios
5. Create telemetry data for analysis

### Customizing Test Script

You can modify the test script variables:

```bash
# Edit test_script.sh
BASE_URL="http://localhost:8080"  # Change if app runs on different port
DELAY_BETWEEN_REQUESTS=2          # Delay between individual requests
LOOP_COUNT=10                     # Number of test cycles
```

## Manual Testing

You can also test endpoints manually:

```bash
# Test hello endpoint
curl http://localhost:8080/api/hello

# Test user creation
curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"John Doe","email":"john@example.com"}'

# Test error endpoint
curl http://localhost:8080/api/error-demo

# Check metrics
curl http://localhost:8080/actuator/metrics
```

## OpenTelemetry Data

The application generates the following telemetry data:

### Traces
- HTTP request spans (automatic)
- Custom business logic spans (manual)
- Error spans with stack traces
- Span attributes for request/response data

### Metrics
- HTTP request metrics (count, duration, error rate)
- JVM metrics (memory, GC, threads)
- Custom business metrics
- Spring Boot actuator metrics

### Logs
- Application logs with correlation IDs
- Error logs with stack traces
- Request/response logging
- Performance logging

## Troubleshooting

### Application Won't Start

1. Check Java version: `java -version`
2. Check Maven: `mvn -version`
3. Verify port 8080 is available
4. Check OpenTelemetry agent download

### No Telemetry Data

1. Verify environment variables are set correctly
2. Check collector/backend is running and accessible
3. Verify network connectivity to telemetry endpoints
4. Check application logs for OpenTelemetry errors

### Test Script Fails

1. Ensure application is running on port 8080
2. Check if curl is installed
3. Verify network connectivity
4. Check application logs for errors

### Port Conflicts

If you encounter port conflicts with the OpenTelemetry collector:

1. Check what's using the ports: `lsof -i :14317`
2. Stop conflicting services
3. Or modify the port mappings in `docker-compose.yml`

## Development

### Building

```bash
mvn clean compile
```

### Running Tests

```bash
mvn test
```

### Package

```bash
mvn clean package
```

### Running with JAR

```bash
java -javaagent:otel-javaagent.jar -jar target/springboot-otel-demo-1.0.0.jar
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License. 