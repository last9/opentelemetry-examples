package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"

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
	config.Consumer.Group.Rebalance.Strategy = sarama.BalanceStrategyRoundRobin
	config.Consumer.Offsets.Initial = sarama.OffsetOldest

	// Create consumer group
	group := "hello-world-consumer-group"
	topic := "hello-world-topic"

	consumerGroup, err := sarama.NewConsumerGroup([]string{"localhost:9092"}, group, config)
	if err != nil {
		log.Fatalf("Failed to create consumer group: %v", err)
	}
	defer consumerGroup.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Create consumer handler and wrap it with OpenTelemetry instrumentation
	handler := &ConsumerGroupHandler{}
	wrappedHandler := otelsarama.WrapConsumerGroupHandler(handler)

	// Handle shutdown signals
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, os.Interrupt)
	go func() {
		<-sigchan
		log.Println("Caught shutdown signal. Cancelling consumer group...")
		cancel()
	}()

	// Start consuming
	fmt.Printf("Starting consumer group %s\n", group)
	for {
		err := consumerGroup.Consume(ctx, []string{topic}, wrappedHandler)
		if err != nil {
			if err == context.Canceled {
				break
			}
			log.Printf("Error from consumer: %v", err)
		}
		if ctx.Err() != nil {
			break
		}
	}

	fmt.Println("Consumer shut down")
}

// ConsumerGroupHandler represents the consumer group handler
type ConsumerGroupHandler struct{}

func (h *ConsumerGroupHandler) Setup(_ sarama.ConsumerGroupSession) error   { return nil }
func (h *ConsumerGroupHandler) Cleanup(_ sarama.ConsumerGroupSession) error { return nil }

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

func (h *ConsumerGroupHandler) ConsumeClaim(session sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	for {
		select {
		case message := <-claim.Messages():
			if message == nil {
				return nil
			}

			printMessage(message)
			session.MarkMessage(message, "")

		case <-session.Context().Done():
			return nil
		}
	}
}
