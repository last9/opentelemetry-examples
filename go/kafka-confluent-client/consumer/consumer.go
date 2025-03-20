package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"time"

	"kafka-hello-world/last9"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

func main() {
	// Initialize instrumentation
	instrumentation := last9.NewInstrumentation()
	defer instrumentation.TracerProvider.Shutdown(context.Background())

	// Create Kafka consumer
	c, err := kafka.NewConsumer(&kafka.ConfigMap{
		"bootstrap.servers":  "localhost:9092",
		"group.id":          "hello-world-group",
		"auto.offset.reset": "earliest",
	})
	if err != nil {
		log.Fatalf("Failed to create consumer: %v", err)
	}
	defer c.Close()

	// Subscribe to topic
	topic := "hello-world-topic"
	err = c.SubscribeTopics([]string{topic}, nil)
	if err != nil {
		log.Fatalf("Failed to subscribe to topic: %v", err)
	}

	// Create a signal channel for graceful shutdown
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, os.Interrupt)

	run := true
	tracer := otel.Tracer("kafka-consumer")

	for run {
		select {
		case <-sigchan:
			fmt.Println("Caught shutdown signal. Closing consumer...")
			run = false
		default:
			msg, err := c.ReadMessage(time.Second)
			if err != nil {
				if !err.(kafka.Error).IsTimeout() {
					log.Printf("Consumer error: %v\n", err)
				}
				continue
			}

			// Extract trace context from message headers
			carrier := make(map[string]string)
			for _, header := range msg.Headers {
				carrier[header.Key] = string(header.Value)
			}

			// Create trace context from headers
			ctx := otel.GetTextMapPropagator().Extract(context.Background(),
				NewKafkaHeadersCarrier(&carrier))

			// Start a new span
			ctx, span := tracer.Start(ctx, "consume_message",
				trace.WithAttributes(
					attribute.String("messaging.system", "kafka"),
					attribute.String("messaging.operation", "receive"),
					attribute.String("messaging.destination", *msg.TopicPartition.Topic),
					attribute.Int64("messaging.kafka.partition", int64(msg.TopicPartition.Partition)),
					attribute.Int64("messaging.kafka.offset", int64(msg.TopicPartition.Offset)),
				))

			// Process the message
			log.Printf("Message on %s: %s\n",
				msg.TopicPartition, string(msg.Value))

			span.End()
		}
	}
}

// KafkaHeadersCarrier implements TextMapCarrier for Kafka headers
type KafkaHeadersCarrier struct {
	headers *map[string]string
}

func NewKafkaHeadersCarrier(headers *map[string]string) *KafkaHeadersCarrier {
	return &KafkaHeadersCarrier{headers: headers}
}

func (c *KafkaHeadersCarrier) Get(key string) string {
	return (*c.headers)[key]
}

func (c *KafkaHeadersCarrier) Set(key string, value string) {
	(*c.headers)[key] = value
}

func (c *KafkaHeadersCarrier) Keys() []string {
	keys := make([]string, 0, len(*c.headers))
	for k := range *c.headers {
		keys = append(keys, k)
	}
	return keys
}
