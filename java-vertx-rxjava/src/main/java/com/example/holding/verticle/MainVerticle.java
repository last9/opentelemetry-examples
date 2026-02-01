package com.example.holding.verticle;

import com.example.holding.rest.FetchHoldingsHandler;
import com.example.holding.rest.HealthCheckHandler;
import com.example.holding.rest.PlaceOrderHandler;
import com.example.holding.services.GraphQLService;
import com.example.holding.services.HoldingService;
import com.example.holding.services.OrderService;
import io.reactivex.rxjava3.core.Completable;
import io.vertx.rxjava3.core.AbstractVerticle;
import io.vertx.rxjava3.ext.web.Router;
import io.vertx.rxjava3.ext.web.handler.BodyHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class MainVerticle extends AbstractVerticle {
    private static final Logger log = LoggerFactory.getLogger(MainVerticle.class);
    private static final int PORT = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));

    @Override
    public Completable rxStart() {
        // Initialize services
        HoldingService holdingService = new HoldingService();
        GraphQLService graphQLService = new GraphQLService();
        OrderService orderService = new OrderService();

        // Initialize handlers
        FetchHoldingsHandler fetchHoldingsHandler = new FetchHoldingsHandler(holdingService, graphQLService);
        PlaceOrderHandler placeOrderHandler = new PlaceOrderHandler(orderService);
        HealthCheckHandler healthCheckHandler = new HealthCheckHandler();

        // Create router
        Router router = Router.router(vertx);

        // Enable body handling for POST requests
        router.route().handler(BodyHandler.create());

        // Health check endpoint
        router.get("/health").handler(healthCheckHandler::health);

        // Holdings API - /v1/holding
        router.get("/v1/holding").handler(fetchHoldingsHandler::fetchAllHoldings);

        // Order API - /v1/order/create
        router.post("/v1/order/create").handler(placeOrderHandler::placeOrder);

        // Start HTTP server
        return vertx.createHttpServer()
                .requestHandler(router)
                .rxListen(PORT)
                .doOnSuccess(server -> log.info("HTTP server started on port {}", PORT))
                .doOnError(err -> log.error("Failed to start HTTP server", err))
                .ignoreElement();
    }
}
