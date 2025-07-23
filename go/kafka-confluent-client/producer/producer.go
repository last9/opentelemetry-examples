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

	// Create Kafka producer
	p, err := kafka.NewProducer(&kafka.ConfigMap{
		"bootstrap.servers": "localhost:9092",
		"client.id":        "hello-world-producer",
		"acks":             "all",
	})
	if err != nil {
		log.Fatalf("Failed to create producer: %v", err)
	}
	defer p.Close()

	// Create a signal channel for graceful shutdown
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, os.Interrupt)

	// Start delivery report goroutine
	go func() {
		for e := range p.Events() {
			switch ev := e.(type) {
			case *kafka.Message:
				if ev.TopicPartition.Error != nil {
					log.Printf("Failed to deliver message: %v\n", ev.TopicPartition.Error)
				} else {
					log.Printf("Successfully produced message to topic %s partition [%d] @ offset %v\n",
						*ev.TopicPartition.Topic, ev.TopicPartition.Partition, ev.TopicPartition.Offset)
				}
			}
		}
	}()

	topic := "hello-world-topic"
	counter := 0
	run := true

	tracer := otel.Tracer("kafka-producer")

	for run {
		select {
		case <-sigchan:
			fmt.Println("Caught shutdown signal. Closing producer...")
			run = false
		default:
			message := fmt.Sprintf("Hello, World! #%d", counter)
			
			// Create a new trace span for the message
			ctx, span := tracer.Start(context.Background(), "produce_message",
				trace.WithSpanKind(trace.SpanKindProducer),
				trace.WithAttributes(
					attribute.String("messaging.system", "kafka"),
					attribute.String("messaging.operation", "publish"),
					attribute.String("messaging.destination", topic),
					attribute.Int("message_counter", counter),
				))

			// Extract trace context
			carrier := make(map[string]string)
			otel.GetTextMapPropagator().Inject(ctx, NewKafkaHeadersCarrier(&carrier))

			// Create message headers with trace context
			var headers []kafka.Header
			for k, v := range carrier {
				headers = append(headers, kafka.Header{
					Key:   k,
					Value: []byte(v),
				})
			}

			// Produce message
			err = p.Produce(&kafka.Message{
				TopicPartition: kafka.TopicPartition{
					Topic:     &topic,
					Partition: kafka.PartitionAny,
				},
				Key:     []byte(fmt.Sprintf("key-%d", counter)),
				Value:   []byte(message),
				Headers: headers,
			}, nil)

			if err != nil {
				log.Printf("Failed to produce message: %v\n", err)
				span.RecordError(err)
			}

			span.End()
			counter++
			time.Sleep(1 * time.Second)
		}
	}

	// Wait for messages to be delivered
	p.Flush(15 * 1000)
	fmt.Println("Producer shut down")
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
