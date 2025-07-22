package last9

import (
	"context"

	amqp "github.com/rabbitmq/amqp091-go"
)

// MessageBroker defines the interface for message queue operations
type MessageBroker interface {
	PublishMessage(ctx context.Context, queueName string, data []byte) error
	ConsumeMessages(ctx context.Context, queueName string) (<-chan Message, error)
	AckMessage(ctx context.Context, msg *amqp.Delivery) error
	NackMessage(ctx context.Context, msg *amqp.Delivery, requeue bool) error
}

// Define the Message type in the same file
type Message struct {
	Body     []byte
	Original *amqp.Delivery
	Context  context.Context
}
