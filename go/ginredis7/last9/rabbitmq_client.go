package last9

import (
	"context"
	"fmt"

	amqp "github.com/rabbitmq/amqp091-go"
	"go.opentelemetry.io/otel/trace"
)

type RabbitMQConfig struct {
	Host     string
	Port     string
	Username string
	Password string
	VHost    string
}

type RabbitMQClient struct {
	conn    *amqp.Connection
	channel *amqp.Channel
	tracer  trace.Tracer
}

func NewRabbitMQClient(config *RabbitMQConfig, tracer trace.Tracer) (*RabbitMQClient, error) {
	// Construct URL
	url := fmt.Sprintf("amqp://%s:%s@%s:%s%s",
		config.Username,
		config.Password,
		config.Host,
		config.Port,
		config.VHost)

	// Create regular connection
	conn, err := amqp.Dial(url)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to RabbitMQ at %s:%s: %v", config.Host, config.Port, err)
	}

	// Create base channel
	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to open channel: %v", err)
	}

	return &RabbitMQClient{
		conn:    conn,
		channel: ch,
		tracer:  tracer,
	}, nil
}

func (c *RabbitMQClient) Close() error {
	if err := c.channel.Close(); err != nil {
		return err
	}
	return c.conn.Close()
}

func (c *RabbitMQClient) DeclareQueue(ctx context.Context, name string) (amqp.Queue, error) {
	return c.channel.QueueDeclare(
		name,
		true,  // durable
		false, // auto-delete
		false, // exclusive
		false, // no-wait
		nil,   // arguments
	)
}

func (c *RabbitMQClient) PublishWithContext(ctx context.Context, exchange, routingKey string, mandatory, immediate bool, msg amqp.Publishing) error {
	return c.channel.PublishWithContext(ctx,
		exchange,
		routingKey,
		mandatory,
		immediate,
		msg,
	)
}

func (c *RabbitMQClient) Consume(ctx context.Context, queue, consumer string, autoAck, exclusive, noLocal, noWait bool, args amqp.Table) (<-chan amqp.Delivery, error) {
	return c.channel.Consume(
		queue,
		consumer,
		autoAck,
		exclusive,
		noLocal,
		noWait,
		args,
	)
}
