package com.example;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import io.opentelemetry.semconv.resource.attributes.ResourceAttributes;

import jakarta.servlet.ServletContextEvent;
import jakarta.servlet.ServletContextListener;
import jakarta.servlet.annotation.WebListener;

import java.io.InputStream;
import java.util.Base64;
import java.util.Properties;

@WebListener
public class OpenTelemetryConfig implements ServletContextListener {

    private static volatile boolean initialized = false;

    @Override
    public void contextInitialized(ServletContextEvent sce) {
        if (!initialized) {
            synchronized (OpenTelemetryConfig.class) {
                if (!initialized) {
                    initializeOpenTelemetry();
                    initialized = true;
                }
            }
        }
    }

    private static void initializeOpenTelemetry() {
        Properties props = new Properties();
        try (InputStream input = OpenTelemetryConfig.class.getClassLoader().getResourceAsStream("last9.properties")) {
            if (input == null) {
                throw new IllegalStateException("Unable to find last9.properties");
            }
            props.load(input);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to load Last9 properties", e);
        }

        String username = props.getProperty("last9.username");
        String password = props.getProperty("last9.password");
        String endpoint = props.getProperty("last9.endpoint");

        if (username == null || password == null || endpoint == null) {
            throw new IllegalStateException("last9.username, last9.password, and last9.endpoint must be set in last9.properties");
        }

        String auth = username + ":" + password;
        String encodedAuth = Base64.getEncoder().encodeToString(auth.getBytes());

        OtlpGrpcSpanExporter spanExporter = OtlpGrpcSpanExporter.builder()
                .setEndpoint(endpoint)
                .addHeader("Authorization", "Basic " + encodedAuth)
                .build();

        Resource resource = Resource.getDefault()
                .merge(Resource.create(Attributes.of(ResourceAttributes.SERVICE_NAME, "tomcat-otel-example")));

        SdkTracerProvider sdkTracerProvider = SdkTracerProvider.builder()
                .setResource(resource)
                .addSpanProcessor(BatchSpanProcessor.builder(spanExporter).build())
                .build();

        OpenTelemetrySdk openTelemetry = OpenTelemetrySdk.builder()
                .setTracerProvider(sdkTracerProvider)
                .buildAndRegisterGlobal();
    }

    @Override
    public void contextDestroyed(ServletContextEvent sce) {
        // Perform cleanup if necessary
    }
}