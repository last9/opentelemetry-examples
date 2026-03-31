package com.example;

import io.nats.client.Connection;
import io.nats.client.Dispatcher;
import io.nats.client.Nats;
import io.nats.client.Options;

import java.nio.charset.StandardCharsets;
import java.time.Duration;

/**
 * Pure NATS publish/subscribe — zero OpenTelemetry imports.
 *
 * Traces are produced automatically by the OTel Java agent extension
 * (opentelemetry-nats-java). No manual span creation needed.
 *
 * Run with:
 *   java -javaagent:opentelemetry-javaagent.jar \
 *        -Dotel.javaagent.extensions=opentelemetry-nats-java-0.1.0.jar \
 *        -Dotel.service.name=nats-auto-demo \
 *        -Dotel.exporter.otlp.endpoint=http://localhost:4318 \
 *        -Dotel.exporter.otlp.protocol=http/protobuf \
 *        -jar target/nats-auto-demo-1.0.0.jar
 */
public class Main {

    public static void main(String[] args) throws Exception {
        String natsUrl = System.getenv().getOrDefault("NATS_URL", "nats://localhost:4222");

        Options options = new Options.Builder()
                .server(natsUrl)
                .connectionTimeout(Duration.ofSeconds(5))
                .build();

        try (Connection nats = Nats.connect(options)) {
            System.out.println("Connected to NATS at " + natsUrl);

            // Subscribe — onMessage() is auto-instrumented with a CONSUMER span
            Dispatcher dispatcher = nats.createDispatcher(msg -> {
                String payload = new String(msg.getData(), StandardCharsets.UTF_8);
                System.out.printf("[%s] received: %s%n", msg.getSubject(), payload);
            });
            dispatcher.subscribe("ticks.ltp");

            // Publish — publishInternal() is auto-instrumented with a PRODUCER span
            // W3C traceparent injected into headers automatically — no code needed here
            for (int i = 1; i <= 5; i++) {
                String payload = String.format(
                        "{\"symbol\":\"AAPL\",\"ltp\":%.2f,\"seq\":%d}", 175.0 + i, i);
                nats.publish("ticks.ltp", payload.getBytes(StandardCharsets.UTF_8));
                System.out.printf("[publish] %s%n", payload);
                Thread.sleep(500);
            }

            Thread.sleep(2000); // let in-flight messages arrive
        }

        System.out.println("Done.");
    }
}
