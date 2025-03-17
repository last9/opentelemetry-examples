package producer

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
		"bootstrap.servers": "localhost:9092",
		"client.id":         "hello-world-producer",
		"acks":              "all",
	}

	// Create a new producer instance
	producer, err := kafka.NewProducer(config)
	if err != nil {
		log.Fatalf("Failed to create producer: %s", err)
	}
	defer producer.Close()

	// Handle delivery reports
	go func() {
		for e := range producer.Events() {
			switch ev := e.(type) {
			case *kafka.Message:
				if ev.TopicPartition.Error != nil {
					fmt.Printf("Failed to deliver message: %v\n", ev.TopicPartition.Error)
				} else {
					fmt.Printf("Successfully produced message to topic %s (partition %d at offset %d)\n",
						*ev.TopicPartition.Topic, ev.TopicPartition.Partition, ev.TopicPartition.Offset)
				}
			}
		}
	}()

	// Capture SIGINT to cleanly shut down
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, syscall.SIGINT, syscall.SIGTERM)

	// Topic to produce messages to
	topic := "hello-world-topic"

	// Produce messages until SIGINT
	counter := 0
	run := true
	for run {
		select {
		case <-sigchan:
			fmt.Println("Caught shutdown signal. Closing producer...")
			run = false
		default:
			// Create a message to send
			message := fmt.Sprintf("Hello, World! #%d", counter)

			// Produce the message
			err = producer.Produce(&kafka.Message{
				TopicPartition: kafka.TopicPartition{Topic: &topic, Partition: kafka.PartitionAny},
				Value:          []byte(message),
				Key:            []byte(fmt.Sprintf("key-%d", counter)),
			}, nil)

			if err != nil {
				log.Printf("Failed to produce message: %v\n", err)
			}

			counter++
			time.Sleep(1 * time.Second)
		}
	}

	// Wait for message deliveries before shutting down
	producer.Flush(15 * 1000)
	fmt.Println("Producer shut down")
}
