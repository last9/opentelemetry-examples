FROM eclipse-temurin:11-jre
WORKDIR /app
COPY target/resteasy-agent-test-1.0.0.jar app.jar
COPY target/vertx3-otel-agent.jar vertx3-otel-agent.jar
ENTRYPOINT ["java", "-javaagent:vertx3-otel-agent.jar", "-jar", "app.jar"]
