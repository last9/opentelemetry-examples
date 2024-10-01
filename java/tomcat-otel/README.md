# Tomcat Java OpenTelemetry Example

## Setup

1. Copy the properties template file:
   ```
   cp src/main/resources/last9.properties.template src/main/resources/last9.properties
   ```

2. Edit `src/main/resources/last9.properties` and replace the placeholder values with your actual Last9 credentials.

3. Build the project:
   ```
   mvn clean package
   ```

4. Download the OpenTelemetry Java agent JAR file and place it in the project root directory.
   ```
   curl -L https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar -o opentelemetry-javaagent.jar
   ```

5. Deploy the WAR file to your Tomcat server.
   **Example** command on Mac: Use your local Tomcat path
   ```
   cp target/tomcat-otel-example.war /opt/homebrew/Cellar/tomcat/10.1.30/libexec/webapps/
   ```

6. ## Environment Variables

Before running the application, make sure to set the following environment variables in your `start.sh` script or your environment:

- `OTEL_EXPORTER_OTLP_ENDPOINT`: The endpoint for your OpenTelemetry collector (default: https://otlp.last9.io)
- `OTEL_SERVICE_NAME`: The name of your service (default: tomcat-otel-example)
- `OTEL_EXPORTER_OTLP_USERNAME`: Your Last9 username (if using basic auth)
- `OTEL_EXPORTER_OTLP_HEADERS`: Additional headers for the OTLP exporter (optional)
- `OTEL_TRACES_EXPORTER: otlp`
- `OTEL_METRICS_EXPORTER: otlp`
- `OTEL_LOGS_EXPORTER: otlp`
- `OTEL_EXPORTER_OTLP_PROTOCOL: http/protobuf`
- `OTEL_METRIC_EXPORT_INTERVAL: 60000`

7. Start Tomcat using the `start.sh` script:
   ```
   ./start.sh
   ```

## Accessing the Application

Once Tomcat is running, you can access the application at:

http://localhost:8080/tomcat-otel-example/hello

This will display a simple "Hello, OpenTelemetry!" message and generate telemetry data that will be sent to your Last9 account.

## Troubleshooting

If you encounter any issues, check the Tomcat logs for error messages. Ensure that the OpenTelemetry Java agent JAR file is present in the project root directory and that your Last9 credentials are correctly set in the `last9.properties` file.

