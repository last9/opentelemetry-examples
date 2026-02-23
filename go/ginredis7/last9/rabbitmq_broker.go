package last9

import (
	"context"

	amqp "github.com/rabbitmq/amqp091-go"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// amqpHeadersCarrier implements TextMapCarrier for RabbitMQ headers
type amqpHeadersCarrier amqp.Table

// Get retrieves a value from the carrier
func (c amqpHeadersCarrier) Get(key string) string {
	if value, ok := (amqp.Table(c))[key]; ok {
		if str, ok := value.(string); ok {
			return str
		}
	}
	return ""
}

// Set stores a value in the carrier
func (c amqpHeadersCarrier) Set(key string, value string) {
	(amqp.Table(c))[key] = value
}

// Keys lists the keys stored in this carrier
func (c amqpHeadersCarrier) Keys() []string {
	keys := make([]string, 0, len(c))
	for k := range c {
		keys = append(keys, k)
	}
	return keys
}

type RabbitMQBroker struct {
	client *RabbitMQClient
	tracer trace.Tracer
}

func NewRabbitMQBroker(config *RabbitMQConfig) (*RabbitMQBroker, error) {
	// Use global tracer from go-agent
	tracer := otel.Tracer("rabbitmq")

	client, err := NewRabbitMQClient(config, tracer)
	if err != nil {
		return nil, err
	}

	return &RabbitMQBroker{
		client: client,
		tracer: tracer,
	}, nil
}

func (b *RabbitMQBroker) Close() error {
	return b.client.Close()
}

// Add these constants at the top of the file
const (
	messagingSystemRabbitMQ   = "rabbitmq"
	messagingOperationPublish = "publish"
	messagingOperationProcess = "process"
	messagingOperationConsume = "consume"
	messagingOperationAck     = "ack"
	messagingOperationNack    = "nack"
)

func (b *RabbitMQBroker) declareQueue(ctx context.Context, queueName string) (amqp.Queue, error) {
	ctx, span := b.tracer.Start(ctx, "rabbitmq.queue.declare",
		trace.WithAttributes(
			attribute.String("messaging.system", messagingSystemRabbitMQ),
			attribute.String("messaging.destination", queueName),
			attribute.String("messaging.destination_kind", "queue"),
			attribute.String("messaging.operation", "declare"),
			attribute.String("messaging.rabbitmq.queue", queueName),
		))
	defer span.End()

	queue, err := b.client.DeclareQueue(ctx, queueName)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
	}
	return queue, err
}

// Update the helper functions to use our custom carrier
func injectTraceContext(ctx context.Context, headers amqp.Table) amqp.Table {
	if headers == nil {
		headers = make(amqp.Table)
	}
	carrier := amqpHeadersCarrier(headers)
	otel.GetTextMapPropagator().Inject(ctx, carrier)
	return amqp.Table(carrier)
}

func extractTraceContext(ctx context.Context, headers amqp.Table) context.Context {
	carrier := amqpHeadersCarrier(headers)
	return otel.GetTextMapPropagator().Extract(ctx, carrier)
}

func (b *RabbitMQBroker) PublishMessage(ctx context.Context, queueName string, data []byte) error {
	ctx, span := b.tracer.Start(ctx, "rabbitmq.publish",
		trace.WithAttributes(
			attribute.String("messaging.system", messagingSystemRabbitMQ),
			attribute.String("messaging.destination", queueName),
			attribute.String("messaging.destination_kind", "queue"),
			attribute.String("messaging.protocol", "AMQP"),
			attribute.String("messaging.protocol_version", "0.9.1"),
			attribute.String("messaging.operation", messagingOperationPublish),
			attribute.Int("messaging.message_size", len(data)),
			attribute.String("messaging.rabbitmq.routing_key", queueName),
			attribute.String("messaging.rabbitmq.exchange", ""),
		))
	defer span.End()

	// Create headers and inject trace context
	headers := make(amqp.Table)
	carrier := amqpHeadersCarrier(headers)
	otel.GetTextMapPropagator().Inject(ctx, carrier)
	headers = amqp.Table(carrier)

	err := b.client.PublishWithContext(ctx,
		"",        // exchange
		queueName, // routing key
		false,     // mandatory
		false,     // immediate
		amqp.Publishing{
			ContentType: "application/json",
			Body:        data,
			Headers:     headers,
		},
	)

	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
	}
	return err
}

// Update the ConsumeMessages method to use the Message type from the interface
func (b *RabbitMQBroker) ConsumeMessages(ctx context.Context, queueName string) (<-chan Message, error) {
	ctx, span := b.tracer.Start(ctx, "rabbitmq.consume.setup",
		trace.WithAttributes(
			attribute.String("messaging.system", messagingSystemRabbitMQ),
			attribute.String("messaging.destination", queueName),
			attribute.String("messaging.destination_kind", "queue"),
			attribute.String("messaging.protocol", "AMQP"),
			attribute.String("messaging.protocol_version", "0.9.1"),
			attribute.String("messaging.operation", messagingOperationConsume),
			attribute.String("messaging.rabbitmq.queue", queueName),
		))
	defer span.End()

	// Ensure queue exists
	_, err := b.declareQueue(ctx, queueName)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return nil, err
	}

	deliveries, err := b.client.Consume(
		ctx,
		queueName, // queue
		"",        // consumer
		false,     // auto-ack
		false,     // exclusive
		false,     // no-local
		false,     // no-wait
		nil,       // args
	)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return nil, err
	}

	messages := make(chan Message)

	go func() {
		defer close(messages)
		for d := range deliveries {
			// Extract the parent context from the message headers
			parentCtx := extractTraceContext(ctx, d.Headers)

			// Now create message processing span as child of the extracted context
			messages <- Message{
				Body:     d.Body,
				Original: &d,
				Context:  parentCtx, // Pass the extracted context with the message
			}
		}
	}()

	return messages, nil
}

// Update the Ack/Nack methods to accept the delivery
func (b *RabbitMQBroker) AckMessage(ctx context.Context, msg *amqp.Delivery) error {
	// Create ack span as child of the provided context
	ctx, span := b.tracer.Start(ctx, "rabbitmq.ack",
		trace.WithAttributes(
			attribute.String("messaging.system", messagingSystemRabbitMQ),
			attribute.String("messaging.operation", messagingOperationAck),
			attribute.String("messaging.message_id", msg.MessageId),
			attribute.String("messaging.conversation_id", msg.CorrelationId),
			attribute.String("messaging.rabbitmq.routing_key", msg.RoutingKey),
			attribute.String("messaging.rabbitmq.consumer_tag", msg.ConsumerTag),
			attribute.Int64("messaging.rabbitmq.delivery_tag", int64(msg.DeliveryTag)),
		))
	defer span.End()

	err := msg.Ack(false)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
	}
	return err
}

func (b *RabbitMQBroker) NackMessage(ctx context.Context, msg *amqp.Delivery, requeue bool) error {
	// Create nack span as child of the provided context
	ctx, span := b.tracer.Start(ctx, "rabbitmq.nack",
		trace.WithAttributes(
			attribute.String("messaging.system", messagingSystemRabbitMQ),
			attribute.String("messaging.operation", messagingOperationNack),
			attribute.String("messaging.message_id", msg.MessageId),
			attribute.String("messaging.conversation_id", msg.CorrelationId),
			attribute.String("messaging.rabbitmq.routing_key", msg.RoutingKey),
			attribute.String("messaging.rabbitmq.consumer_tag", msg.ConsumerTag),
			attribute.Int64("messaging.rabbitmq.delivery_tag", int64(msg.DeliveryTag)),
			attribute.Bool("messaging.rabbitmq.requeue", requeue),
		))
	defer span.End()

	err := msg.Nack(false, requeue)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
	}
	return err
}
