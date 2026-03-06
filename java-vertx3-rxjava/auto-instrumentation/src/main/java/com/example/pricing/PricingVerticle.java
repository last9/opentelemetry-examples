package com.example.pricing;

import io.reactivex.Completable;
import io.vertx.core.json.JsonObject;
import io.vertx.reactivex.core.AbstractVerticle;
import io.vertx.reactivex.ext.web.Router;
import io.vertx.reactivex.ext.web.RoutingContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.Map;
import java.util.Random;

/**
 * Pricing Service Verticle.
 * Demonstrates distributed tracing by serving as a downstream service.
 */
public class PricingVerticle extends AbstractVerticle {

    private static final Logger logger = LoggerFactory.getLogger(PricingVerticle.class);

    private final Random random = new Random();
    private final Map<String, Double> basePrices = new HashMap<>();

    @Override
    public Completable rxStart() {
        logger.info("Starting PricingVerticle...");

        // Initialize some base prices
        basePrices.put("AAPL", 175.50);
        basePrices.put("GOOGL", 140.25);
        basePrices.put("MSFT", 378.00);
        basePrices.put("AMZN", 178.50);
        basePrices.put("TSLA", 245.00);
        basePrices.put("NVDA", 875.00);

        // Plain router — auto-instrumented by RouterImplAdvice
        Router router = Router.router(vertx);

        // Health check
        router.get("/health").handler(this::handleHealth);

        // Price endpoint
        router.get("/v1/price/:symbol").handler(this::handleGetPrice);

        int port = Integer.parseInt(getEnvOrDefault("APP_PORT", "8081"));

        return vertx.createHttpServer()
                .requestHandler(router)
                .rxListen(port)
                .doOnSuccess(server -> logger.info("Pricing service started on port {}", port))
                .ignoreElement();
    }

    private void handleHealth(RoutingContext ctx) {
        ctx.response()
                .putHeader("content-type", "application/json")
                .end(new JsonObject().put("status", "UP").encode());
    }

    private void handleGetPrice(RoutingContext ctx) {
        String symbol = ctx.pathParam("symbol").toUpperCase();
        logger.info("Price lookup for symbol: {}", symbol);

        // Simulate price with random fluctuation
        double basePrice = basePrices.getOrDefault(symbol, 100.0);
        double fluctuation = (random.nextDouble() - 0.5) * 0.1 * basePrice;
        double currentPrice = Math.round((basePrice + fluctuation) * 100.0) / 100.0;

        // Simulate some latency
        try {
            Thread.sleep(random.nextInt(50) + 10);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        JsonObject response = new JsonObject()
                .put("symbol", symbol)
                .put("price", currentPrice)
                .put("currency", "USD")
                .put("timestamp", System.currentTimeMillis());

        ctx.response()
                .putHeader("content-type", "application/json")
                .end(response.encode());
    }

    private String getEnvOrDefault(String name, String defaultValue) {
        String value = System.getenv(name);
        return value != null ? value : defaultValue;
    }
}
