package com.example.cache

import com.typesafe.scalalogging.LazyLogging
import io.lettuce.core.RedisClient
import io.lettuce.core.api.sync.RedisCommands

// Lettuce Redis client is auto-instrumented by the OTel Java agent.
// Every GET/SET/DEL command produces a span with db.system=redis, db.statement attributes.
class RedisRepository(commands: RedisCommands[String, String]) extends LazyLogging:

  def get(key: String): Option[String] =
    Option(commands.get(key))

  def set(key: String, value: String, ttlSeconds: Long = 300): Unit =
    commands.setex(key, ttlSeconds, value)
    logger.debug(s"Cached key=$key ttl=${ttlSeconds}s")

  def del(key: String): Unit =
    commands.del(key)

object RedisRepository:
  def apply(host: String, port: Int): RedisRepository =
    val client = RedisClient.create(s"redis://$host:$port")
    val conn   = client.connect()
    new RedisRepository(conn.sync())
