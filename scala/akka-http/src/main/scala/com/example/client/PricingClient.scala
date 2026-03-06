package com.example.client

import com.typesafe.scalalogging.LazyLogging
import org.apache.pekko.actor.typed.ActorSystem
import org.apache.pekko.http.scaladsl.Http
import org.apache.pekko.http.scaladsl.model.{HttpRequest, Uri}
import org.apache.pekko.http.scaladsl.unmarshalling.Unmarshal
import spray.json.DefaultJsonProtocol.*
import spray.json.*

import scala.concurrent.{ExecutionContext, Future}

case class PriceResponse(portfolioId: Int, price: Double, currency: String)

object PriceResponseProtocol extends DefaultJsonProtocol:
  given priceFormat: RootJsonFormat[PriceResponse] = jsonFormat3(PriceResponse.apply)

// The OTel Java agent auto-instruments outgoing Pekko/Akka HTTP client requests.
// The agent injects W3C traceparent headers so the downstream service participates
// in the same distributed trace.
class PricingClient(baseUrl: String)(using system: ActorSystem[?], ec: ExecutionContext)
    extends LazyLogging:

  import PriceResponseProtocol.given

  def getPrice(portfolioId: Int): Future[PriceResponse] =
    val uri = Uri(s"$baseUrl/prices/$portfolioId")
    logger.info(s"Fetching price for portfolioId=$portfolioId from $uri")
    Http()
      .singleRequest(HttpRequest(uri = uri))
      .flatMap { resp =>
        import org.apache.pekko.http.scaladsl.marshallers.sprayjson.SprayJsonSupport.*
        Unmarshal(resp.entity).to[PriceResponse]
      }
      .recover { case ex =>
        logger.warn(s"Pricing service unavailable, using fallback price. reason=${ex.getMessage}")
        PriceResponse(portfolioId, 100.0, "USD")
      }
