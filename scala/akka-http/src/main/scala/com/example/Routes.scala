package com.example

import com.example.cache.RedisRepository
import com.example.client.PricingClient
import com.example.db.{Portfolio, PortfolioRepository}
import com.example.messaging.KafkaEventProducer
import com.example.storage.AerospikeRepository
import com.typesafe.scalalogging.LazyLogging
import io.opentelemetry.api.trace.{SpanKind, StatusCode}
import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.http.scaladsl.marshallers.sprayjson.SprayJsonSupport.*
import org.apache.pekko.http.scaladsl.model.{ContentTypes, HttpEntity, StatusCodes}
import org.apache.pekko.http.scaladsl.server.Directives.*
import org.apache.pekko.http.scaladsl.server.Route
import spray.json.DefaultJsonProtocol.*
import spray.json.*

import scala.concurrent.ExecutionContext
import scala.util.{Failure, Success}

// JSON protocol for request/response models
object JsonProtocol extends DefaultJsonProtocol:
  given portfolioFormat: RootJsonFormat[Portfolio]              = jsonFormat4(Portfolio.apply)
  given createReqFormat: RootJsonFormat[CreatePortfolioRequest] = jsonFormat3(CreatePortfolioRequest.apply)
  // Explicit list format disambiguates between listFormat and seqFormat in Scala 3
  given portfolioListFormat: RootJsonFormat[List[Portfolio]]    = listFormat[Portfolio]

case class CreatePortfolioRequest(name: String, userId: String, balance: Double)

class Routes(
  portfolioRepo: PortfolioRepository,
  redisRepo:     RedisRepository,
  kafkaProducer: KafkaEventProducer,
  aerospikeRepo: AerospikeRepository,
  pricingClient: PricingClient,
)(using system: ActorSystem[?], ec: ExecutionContext) extends LazyLogging:

  import JsonProtocol.given
  import com.example.client.PriceResponseProtocol.given

  val routes: Route = concat(
    // Health check — no span needed, keep it lightweight
    path("health") {
      get { complete(StatusCodes.OK, "OK") }
    },

    path("portfolios") {
      concat(
        // List all portfolios
        get {
          Telemetry.withSpan("GET /portfolios", SpanKind.SERVER) { span =>
            val portfolios = portfolioRepo.findAll()
            span.setAttribute("portfolios.count", portfolios.size.toLong)
            logger.info(s"Fetched ${portfolios.size} portfolios")
            complete(portfolios)
          }
        },

        // Create portfolio — writes to PostgreSQL, caches in Redis, publishes to Kafka
        post {
          entity(as[CreatePortfolioRequest]) { req =>
            Telemetry.withSpan("POST /portfolios", SpanKind.SERVER) { span =>
              span.setAttribute("portfolio.name", req.name)
              span.setAttribute("portfolio.userId", req.userId)

              val portfolio = portfolioRepo.create(req.name, req.userId, req.balance)

              // Cache the new portfolio
              redisRepo.set(s"portfolio:${portfolio.id}", portfolio.toJson.compactPrint)

              // Publish creation event to Kafka
              kafkaProducer.publish(
                portfolio.id.toString,
                s"""{"event":"portfolio.created","id":${portfolio.id},"userId":"${portfolio.userId}"}"""
              )

              // Store in Aerospike for fast lookups
              aerospikeRepo.put("portfolios", portfolio.id.toString, Map("name" -> portfolio.name, "balance" -> portfolio.balance.toString))

              logger.info(s"Created portfolio id=${portfolio.id} userId=${portfolio.userId}")
              complete(StatusCodes.Created, portfolio)
            }
          }
        }
      )
    },

    path("portfolios" / IntNumber) { id =>
      get {
        Telemetry.withSpan("GET /portfolios/:id", SpanKind.SERVER) { span =>
          span.setAttribute("portfolio.id", id.toLong)

          // Check Redis cache first
          redisRepo.get(s"portfolio:$id") match
            case Some(cached) =>
              span.setAttribute("cache.hit", true)
              logger.info(s"Cache hit for portfolio id=$id")
              complete(cached.parseJson.convertTo[Portfolio])
            case None =>
              span.setAttribute("cache.hit", false)
              portfolioRepo.findById(id) match
                case Some(p) =>
                  redisRepo.set(s"portfolio:$id", p.toJson.compactPrint)
                  complete(p)
                case None =>
                  complete(StatusCodes.NotFound, s"Portfolio $id not found")
        }
      }
    },

    // Fetch price from external pricing service (demonstrates HTTP client trace propagation).
    // Note: withSpan is NOT used here because the HTTP call is async (Future-based). The span
    // must be ended inside the onComplete callback, after the Future resolves, not at the point
    // where onComplete registers the callback.
    path("portfolios" / IntNumber / "price") { id =>
      get {
        val span  = Telemetry.tracer.spanBuilder("GET /portfolios/:id/price").setSpanKind(SpanKind.SERVER).startSpan()
        val scope = span.makeCurrent()
        span.setAttribute("portfolio.id", id.toLong)
        onComplete(pricingClient.getPrice(id)) {
          case Success(price) =>
            span.setAttribute("price.value", price.price)
            scope.close()
            span.end()
            complete(price)
          case Failure(ex) =>
            span.recordException(ex)
            span.setStatus(StatusCode.ERROR, ex.getMessage)
            scope.close()
            span.end()
            complete(StatusCodes.ServiceUnavailable, s"Pricing service error: ${ex.getMessage}")
        }
      }
    },

    // Mock pricing endpoint — the service calls itself to demonstrate outbound HTTP trace propagation.
    // In a real system this would be a separate downstream service.
    path("prices" / IntNumber) { id =>
      get {
        Telemetry.withSpan("GET /prices/:id", SpanKind.SERVER) { span =>
          span.setAttribute("portfolio.id", id.toLong)
          val price = 100.0 + (id * 0.5)
          val json  = s"""{"portfolioId":$id,"price":$price,"currency":"USD"}"""
          complete(HttpEntity(ContentTypes.`application/json`, json))
        }
      }
    },

    // Aerospike fast-lookup endpoint
    path("portfolios" / IntNumber / "aerospike") { id =>
      get {
        Telemetry.withSpan("GET /portfolios/:id/aerospike", SpanKind.SERVER) { span =>
          span.setAttribute("portfolio.id", id.toLong)
          aerospikeRepo.get("portfolios", id.toString) match
            case Some(data) => complete(data.map { case (k, v) => k -> v.toString }.toJson.compactPrint)
            case None       => complete(StatusCodes.NotFound, s"No Aerospike record for portfolio $id")
        }
      }
    }
  )
