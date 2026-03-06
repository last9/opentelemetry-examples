package com.example.storage

import com.aerospike.client.{AerospikeClient, Bin, Key}
import com.example.Telemetry
import com.typesafe.scalalogging.LazyLogging
import io.opentelemetry.api.trace.SpanKind

import scala.jdk.CollectionConverters.*

// The OTel Java agent does NOT auto-instrument the Aerospike client.
// Manual spans are added here to produce db.aerospike traces with standard attributes.
class AerospikeRepository(client: AerospikeClient, namespace: String) extends LazyLogging:

  def get(setName: String, key: String): Option[Map[String, AnyRef]] =
    Telemetry.withSpan("aerospike.get", SpanKind.CLIENT) { span =>
      span.setAttribute("db.system", "aerospike")
      span.setAttribute("db.name", namespace)
      span.setAttribute("aerospike.set", setName)
      span.setAttribute("aerospike.key", key)
      val record = client.get(null, Key(namespace, setName, key))
      Option(record).map(_.bins.asScala.toMap)
    }

  def put(setName: String, key: String, bins: Map[String, AnyRef]): Unit =
    Telemetry.withSpan("aerospike.put", SpanKind.CLIENT) { span =>
      span.setAttribute("db.system", "aerospike")
      span.setAttribute("db.name", namespace)
      span.setAttribute("aerospike.set", setName)
      span.setAttribute("aerospike.key", key)
      val asBins = bins.map { case (k, v) => Bin(k, v.toString) }.toArray
      client.put(null, Key(namespace, setName, key), asBins*)
      logger.debug(s"Aerospike put namespace=$namespace set=$setName key=$key")
    }

object AerospikeRepository:
  def apply(host: String, port: Int, namespace: String): AerospikeRepository =
    new AerospikeRepository(AerospikeClient(host, port), namespace)
