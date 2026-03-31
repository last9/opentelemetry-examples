package com.example;

import io.nats.client.Connection;
import io.nats.client.Message;
import io.nats.client.impl.Headers;
import io.nats.client.impl.NatsMessage;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.context.propagation.TextMapSetter;

import java.nio.charset.StandardCharsets;

/**
 * Publishes messages to a NATS subject with OTel trace context injected into headers.
 *
 * The OTel Java agent does NOT auto-instrument the NATS client.
 * Manual spans are created here following messaging semantic conventions.
 * W3C traceparent/tracestate headers carry context to subscribers.
 */
public class NatsPublisher {

    // TextMapSetter bridges OTel context propagation to NATS message headers
    private static final TextMapSetter<Headers> SETTER = Headers::put;

    private final Connection nats;

    public NatsPublisher(Connection nats) {
        this.nats = nats;
    }

    public void publish(String subject, String payload) {
        Telemetry.withSpan(subject + " publish", SpanKind.PRODUCER, span -> {
            span.setAttribute("messaging.system", "nats");
            span.setAttribute("messaging.destination", subject);
            span.setAttribute("messaging.destination_kind", "topic");
            span.setAttribute("messaging.message_payload_size_bytes", payload.length());

            Headers headers = new Headers();
            // Inject W3C traceparent/tracestate so the subscriber can link spans
            Telemetry.get().getPropagators().getTextMapPropagator()
                    .inject(Telemetry.currentContext(), headers, SETTER);

            Message msg = NatsMessage.builder()
                    .subject(subject)
                    .headers(headers)
                    .data(payload.getBytes(StandardCharsets.UTF_8))
                    .build();

            nats.publish(msg);
        });
    }
}
