package consumer

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/confluentinc/confluent-kafka-go/kafka"
)

func main() {
	// Kafka configuration
	config := &kafka.ConfigMap{
		"bootstrap.servers":  "localhost:9092",
		"group.id":           "hello-world-consumer-group",
		"auto.offset.reset":  "earliest",
		"enable.auto.commit": "true",
	}

	// Create a new consumer instance
	consumer, err := kafka.NewConsumer(config)
	if err != nil {
		log.Fatalf("Failed to create consumer: %s", err)
	}
	defer consumer.Close()

	// Subscribe to the topic
	topic := "hello-world-topic"
	err = consumer.SubscribeTopics([]string{topic}, nil)
	if err != nil {
		log.Fatalf("Failed to subscribe to topic %s: %v", topic, err)
	}
	fmt.Printf("Subscribed to topic: %s\n", topic)

	// Capture SIGINT to cleanly shut down
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, syscall.SIGINT, syscall.SIGTERM)

	// Start consuming messages
	run := true
	for run {
		select {
		case sig := <-sigchan:
			fmt.Printf("Caught signal %v: terminating\n", sig)
			run = false
		default:
			// Poll for messages
			ev := consumer.Poll(100)
			if ev == nil {
				continue
			}

			// Process message
			switch e := ev.(type) {
			case *kafka.Message:
				fmt.Printf("Received message: %s\n", string(e.Value))
				// Process the message here
			case kafka.Error:
				fmt.Printf("Error: %v\n", e)
				if e.Code() == kafka.ErrAllBrokersDown {
					run = false
				}
			default:
				// Ignore other event types
			}
		}
	}

	// Wait a bit before closing to make sure all logs are flushed
	time.Sleep(1 * time.Second)
	fmt.Println("Consumer shut down")
}
