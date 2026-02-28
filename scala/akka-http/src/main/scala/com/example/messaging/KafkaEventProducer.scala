package com.example.messaging

import com.typesafe.scalalogging.LazyLogging
import org.apache.kafka.clients.producer.{KafkaProducer, ProducerConfig, ProducerRecord}
import org.apache.kafka.common.serialization.StringSerializer

import java.util.Properties

// Kafka producer is auto-instrumented by the OTel Java agent.
// The agent injects W3C trace context headers into every ProducerRecord, enabling
// trace propagation across service boundaries to Kafka consumers.
class KafkaEventProducer(producer: KafkaProducer[String, String], topic: String) extends LazyLogging:

  def publish(key: String, value: String): Unit =
    val record = ProducerRecord[String, String](topic, key, value)
    producer.send(record, (_, ex) =>
      if ex != null then logger.error(s"Failed to publish event key=$key", ex)
      else logger.info(s"Published event key=$key topic=$topic")
    )

  def close(): Unit = producer.close()

object KafkaEventProducer:
  def apply(bootstrapServers: String, topic: String): KafkaEventProducer =
    val props = Properties()
    props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers)
    props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, classOf[StringSerializer].getName)
    props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, classOf[StringSerializer].getName)
    props.put(ProducerConfig.ACKS_CONFIG, "all")
    props.put(ProducerConfig.RETRIES_CONFIG, "3")
    new KafkaEventProducer(KafkaProducer(props), topic)
