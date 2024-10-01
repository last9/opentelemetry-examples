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

4. Deploy the WAR file to your Tomcat server.

...