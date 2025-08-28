package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"time"

	"kafka-hello-world/last9"

	"github.com/IBM/sarama"
	"github.com/dnwe/otelsarama"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

func main() {
	// Initialize instrumentation
	instrumentation := last9.NewInstrumentation()
	defer instrumentation.TracerProvider.Shutdown(context.Background())

	// Sarama configuration
	config := sarama.NewConfig()
	config.Version = sarama.V2_8_0_0
	config.Producer.Return.Successes = true
	config.Producer.RequiredAcks = sarama.WaitForAll

	// Create a new producer
	producer, err := sarama.NewSyncProducer([]string{"localhost:9092"}, config)
	if err != nil {
		log.Fatalf("Failed to create producer: %v", err)
	}

	// Wrap the producer with OpenTelemetry instrumentation
	producer = otelsarama.WrapSyncProducer(config, producer)
	defer producer.Close()

	// Create a signal channel for graceful shutdown
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, os.Interrupt)

	topic := "hello-world-topic"
	counter := 0
	run := true

	for run {
		select {
		case <-sigchan:
			fmt.Println("Caught shutdown signal. Closing producer...")
			run = false
		default:
			message := fmt.Sprintf("Hello, World! #%d", counter)

			// Create and send message
			msg := &sarama.ProducerMessage{
				Topic: topic,
				Key:   sarama.StringEncoder(fmt.Sprintf("key-%d", counter)),
				Value: sarama.StringEncoder(message),
			}

			partition, offset, err := producer.SendMessage(msg)
			if err != nil {
				log.Printf("Failed to send message: %v\n", err)
			} else {
				fmt.Printf("Message sent to partition %d at offset %d: %s\n",
					partition, offset, message)
			}

			counter++
			time.Sleep(1 * time.Second)
		}
	}

	fmt.Println("Producer shut down")
}

func printMessage(msg *sarama.ConsumerMessage) {
	// Extract tracing info from message
	ctx := otel.GetTextMapPropagator().Extract(context.Background(), otelsarama.NewConsumerMessageCarrier(msg))

	tr := otel.Tracer("consumer")
	_, span := tr.Start(ctx, "consume message", trace.WithAttributes(
		attribute.Key(semconv.MessagingSystemKey).String(semconv.MessagingSystemKafka.Value.AsString()),
		attribute.Key(semconv.MessagingOperationTypeKey).String(semconv.MessagingOperationTypePublish.Value.AsString()),
		attribute.Key("topic").String(msg.Topic),
		attribute.Key("partition").Int64(int64(msg.Partition)),
		attribute.Key("offset").Int64(msg.Offset),
	))
	defer span.End()

	// Process the message
	log.Printf("Message topic:%q partition:%d offset:%d\n\tkey:%s value:%s\n",
		msg.Topic, msg.Partition, msg.Offset,
		string(msg.Key), string(msg.Value))
}
