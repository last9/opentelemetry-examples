package com.example;

import io.nats.client.Connection;
import io.nats.client.Nats;
import io.nats.client.Options;

import java.time.Duration;

public class Main {

    public static void main(String[] args) throws Exception {
        // Boot OTel SDK — reads OTEL_* env vars (service name, endpoint, protocol)
        Telemetry.init();

        String natsUrl = System.getenv().getOrDefault("NATS_URL", "nats://localhost:4222");

        Options options = new Options.Builder()
                .server(natsUrl)
                .connectionTimeout(Duration.ofSeconds(5))
                .reconnectWait(Duration.ofSeconds(1))
                .build();

        try (Connection nats = Nats.connect(options)) {
            System.out.println("Connected to NATS at " + natsUrl);

            NatsSubscriber subscriber = new NatsSubscriber(nats);
            subscriber.subscribe("ticks.ltp");

            NatsPublisher publisher = new NatsPublisher(nats);

            // Publish a few messages so traces appear in Last9
            for (int i = 1; i <= 5; i++) {
                String payload = String.format("{\"symbol\":\"AAPL\",\"ltp\":%.2f,\"seq\":%d}", 175.0 + i, i);
                publisher.publish("ticks.ltp", payload);
                Thread.sleep(500);
            }

            // Keep running to receive any in-flight messages
            Thread.sleep(3000);
        }

        Telemetry.shutdown();
        System.out.println("Done.");
    }
}
