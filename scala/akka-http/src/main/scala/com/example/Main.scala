package com.example

import com.example.cache.RedisRepository
import com.example.client.PricingClient
import com.example.db.PortfolioRepository
import com.example.messaging.KafkaEventProducer
import com.example.storage.AerospikeRepository
import com.typesafe.config.ConfigFactory
import com.typesafe.scalalogging.LazyLogging
import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import org.apache.pekko.http.scaladsl.Http

import scala.concurrent.ExecutionContext
import scala.util.{Failure, Success}

object Main extends LazyLogging:

  def main(args: Array[String]): Unit =
    given system: ActorSystem[Nothing] = ActorSystem(Behaviors.empty, "akka-http-otel")
    given ec: ExecutionContext         = system.executionContext

    val config  = ConfigFactory.load()
    val appConf = config.getConfig("app")

    // Initialise infrastructure clients
    val portfolioRepo = PortfolioRepository(
      url      = appConf.getString("postgres.url"),
      user     = appConf.getString("postgres.user"),
      password = appConf.getString("postgres.password"),
    )
    portfolioRepo.init()

    val redisRepo = RedisRepository(
      host = appConf.getString("redis.host"),
      port = appConf.getInt("redis.port"),
    )

    val kafkaProducer = KafkaEventProducer(
      bootstrapServers = appConf.getString("kafka.bootstrap-servers"),
      topic            = appConf.getString("kafka.topic"),
    )

    val aerospikeRepo = AerospikeRepository(
      host      = appConf.getString("aerospike.host"),
      port      = appConf.getInt("aerospike.port"),
      namespace = appConf.getString("aerospike.namespace"),
    )

    val pricingClient = PricingClient(appConf.getString("pricing-service.url"))

    val routes = Routes(portfolioRepo, redisRepo, kafkaProducer, aerospikeRepo, pricingClient)
    val port   = appConf.getInt("port")

    Http().newServerAt("0.0.0.0", port).bind(routes.routes).onComplete {
      case Success(binding) =>
        logger.info(s"Server started on port $port. Bound to ${binding.localAddress}")
      case Failure(ex) =>
        logger.error("Failed to start server", ex)
        system.terminate()
    }
