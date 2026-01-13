package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"time"

	"github.com/IBM/sarama"
	"github.com/last9/go-agent"
	"github.com/last9/go-agent/integrations/kafka"
)

func main() {
	// Initialize the Last9 agent - this sets up tracing, metrics, and logging
	// Configuration is read from environment variables:
	//   OTEL_EXPORTER_OTLP_ENDPOINT - Last9 OTLP endpoint
	//   OTEL_EXPORTER_OTLP_HEADERS  - Authorization header
	//   OTEL_SERVICE_NAME           - Service name (defaults to "kafka-producer")
	//   OTEL_RESOURCE_ATTRIBUTES    - Additional resource attributes
	if err := agent.Start(); err != nil {
		log.Fatalf("Failed to start Last9 agent: %v", err)
	}
	defer agent.Shutdown()

	// Create an instrumented Kafka producer using go-agent
	// This automatically:
	// - Creates spans for each message sent
	// - Propagates trace context via message headers
	// - Records metrics (messages sent, errors, duration, message size)
	producer, err := kafka.NewSyncProducer(kafka.ProducerConfig{
		Brokers: []string{"localhost:9092"},
		Config:  newSaramaConfig(),
	})
	if err != nil {
		log.Fatalf("Failed to create producer: %v", err)
	}
	defer producer.Close()

	// Create a signal channel for graceful shutdown
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, os.Interrupt)

	topic := "hello-world-topic"
	counter := 0
	run := true

	fmt.Println("Producer started. Press Ctrl+C to stop.")

	for run {
		select {
		case <-sigchan:
			fmt.Println("\nCaught shutdown signal. Closing producer...")
			run = false
		default:
			message := fmt.Sprintf("Hello, World! #%d", counter)

			// Create message
			msg := &sarama.ProducerMessage{
				Topic: topic,
				Key:   sarama.StringEncoder(fmt.Sprintf("key-%d", counter)),
				Value: sarama.StringEncoder(message),
			}

			// Send message with context - trace context is automatically injected
			// into message headers for distributed tracing
			ctx := context.Background()
			partition, offset, err := producer.SendMessage(ctx, msg)
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

// newSaramaConfig creates a Sarama configuration for the producer
func newSaramaConfig() *sarama.Config {
	config := sarama.NewConfig()
	config.Version = sarama.V2_8_0_0
	config.Producer.Return.Successes = true
	config.Producer.RequiredAcks = sarama.WaitForAll
	return config
}
