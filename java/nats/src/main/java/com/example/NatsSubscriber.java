package com.example;

import io.nats.client.Connection;
import io.nats.client.Dispatcher;
import io.nats.client.impl.Headers;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.propagation.TextMapGetter;

import java.nio.charset.StandardCharsets;

/**
 * Subscribes to a NATS subject and extracts OTel context from message headers.
 *
 * Each received message creates a SERVER span linked to the publisher's trace
 * via the W3C traceparent header injected by NatsPublisher.
 */
public class NatsSubscriber {

    // TextMapGetter reads OTel context headers from NATS message headers
    private static final TextMapGetter<Headers> GETTER = new TextMapGetter<>() {
        @Override
        public Iterable<String> keys(Headers headers) {
            return headers.keySet();
        }

        @Override
        public String get(Headers headers, String key) {
            return headers != null ? headers.getFirst(key) : null;
        }
    };

    private final Connection nats;

    public NatsSubscriber(Connection nats) {
        this.nats = nats;
    }

    public Dispatcher subscribe(String subject) {
        Dispatcher dispatcher = nats.createDispatcher(msg -> {
            // Extract upstream trace context from message headers
            Context parentContext = Telemetry.get().getPropagators().getTextMapPropagator()
                    .extract(Context.current(), msg.getHeaders(), GETTER);

            Telemetry.withSpan(subject + " process", SpanKind.CONSUMER, span -> {
                span.setAttribute("messaging.system", "nats");
                span.setAttribute("messaging.destination", subject);
                span.setAttribute("messaging.operation", "receive");

                String payload = new String(msg.getData(), StandardCharsets.UTF_8);
                span.setAttribute("messaging.message_payload_size_bytes", payload.length());

                System.out.printf("[%s] received: %s%n", subject, payload);
            });
        });

        dispatcher.subscribe(subject);
        System.out.printf("Subscribed to subject: %s%n", subject);
        return dispatcher;
    }
}
