package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"

	"github.com/IBM/sarama"
	"github.com/last9/go-agent"
	"github.com/last9/go-agent/integrations/kafka"
)

func main() {
	// Initialize the Last9 agent - this sets up tracing, metrics, and logging
	// Configuration is read from environment variables:
	//   OTEL_EXPORTER_OTLP_ENDPOINT - Last9 OTLP endpoint
	//   OTEL_EXPORTER_OTLP_HEADERS  - Authorization header
	//   OTEL_SERVICE_NAME           - Service name (defaults to "kafka-consumer")
	//   OTEL_RESOURCE_ATTRIBUTES    - Additional resource attributes
	if err := agent.Start(); err != nil {
		log.Fatalf("Failed to start Last9 agent: %v", err)
	}
	defer agent.Shutdown()

	// Consumer group configuration
	group := "hello-world-consumer-group"
	topic := "hello-world-topic"
	brokers := []string{"localhost:9092"}

	// Create consumer group using go-agent
	consumerGroup, err := kafka.NewConsumerGroup(kafka.ConsumerConfig{
		Brokers: brokers,
		GroupID: group,
		Config:  newSaramaConfig(),
	})
	if err != nil {
		log.Fatalf("Failed to create consumer group: %v", err)
	}
	defer consumerGroup.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Create consumer handler and wrap it with go-agent instrumentation
	// This automatically:
	// - Extracts trace context from message headers (producer -> consumer linking)
	// - Creates spans for each message consumed
	// - Records metrics (messages received, errors, processing duration)
	handler := &ConsumerGroupHandler{}
	wrappedHandler := kafka.WrapConsumerGroupHandler(handler)

	// Handle shutdown signals
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, os.Interrupt)
	go func() {
		<-sigchan
		log.Println("\nCaught shutdown signal. Cancelling consumer group...")
		cancel()
	}()

	// Start consuming
	fmt.Printf("Starting consumer group %s, listening on topic %s\n", group, topic)
	fmt.Println("Press Ctrl+C to stop.")

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

// newSaramaConfig creates a Sarama configuration for the consumer
func newSaramaConfig() *sarama.Config {
	config := sarama.NewConfig()
	config.Version = sarama.V2_8_0_0
	config.Consumer.Group.Rebalance.Strategy = sarama.NewBalanceStrategyRoundRobin()
	config.Consumer.Offsets.Initial = sarama.OffsetOldest
	config.Consumer.Return.Errors = true
	return config
}

// ConsumerGroupHandler implements sarama.ConsumerGroupHandler
type ConsumerGroupHandler struct{}

func (h *ConsumerGroupHandler) Setup(_ sarama.ConsumerGroupSession) error   { return nil }
func (h *ConsumerGroupHandler) Cleanup(_ sarama.ConsumerGroupSession) error { return nil }

func (h *ConsumerGroupHandler) ConsumeClaim(session sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	// The trace context is already extracted and available in session.Context()
	// thanks to the go-agent wrapper
	for {
		select {
		case message := <-claim.Messages():
			if message == nil {
				return nil
			}

			// Process the message - trace context is automatically available
			// in session.Context() for any downstream operations
			log.Printf("Message received: topic=%q partition=%d offset=%d key=%s value=%s\n",
				message.Topic,
				message.Partition,
				message.Offset,
				string(message.Key),
				string(message.Value))

			// Mark message as processed
			session.MarkMessage(message, "")

		case <-session.Context().Done():
			return nil
		}
	}
}
