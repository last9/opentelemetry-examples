package com.example.holding;

import com.example.holding.model.Holding;
import com.example.holding.repository.HoldingRepository;
import com.example.holding.service.HoldingService;
import io.last9.tracing.otel.v3.ClientTracing;
import io.last9.tracing.otel.v3.TracedRouter;
import io.last9.tracing.otel.v3.TracedSQLClient;
import io.last9.tracing.otel.v3.TracedWebClient;
import io.reactivex.Completable;
import io.vertx.core.json.JsonArray;
import io.vertx.core.json.JsonObject;
import io.vertx.reactivex.core.AbstractVerticle;
import io.vertx.reactivex.ext.jdbc.JDBCClient;
import io.vertx.reactivex.ext.sql.SQLClient;
import io.vertx.reactivex.ext.web.Router;
import io.vertx.reactivex.ext.web.RoutingContext;
import io.vertx.reactivex.ext.web.client.WebClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Main Verticle for the Holding Service.
 * Demonstrates Vert.x 3 with RxJava2 and automatic OpenTelemetry instrumentation.
 *
 * Tracing features used:
 * - TracedRouter:     automatic SERVER spans for every inbound HTTP request
 * - TracedSQLClient:  automatic CLIENT spans for every SQL query
 * - ClientTracing:    manual traceparent injection for outbound WebClient requests
 * - TracedWebClient:  drop-in WebClient replacement with automatic traceparent injection
 */
public class MainVerticle extends AbstractVerticle {

    private static final Logger logger = LoggerFactory.getLogger(MainVerticle.class);

    private HoldingService holdingService;
    private WebClient webClient;
    private WebClient tracedWebClient;
    private String pricingServiceUrl;

    @Override
    public Completable rxStart() {
        logger.info("Starting MainVerticle...");

        // Initialize JDBC client with TracedSQLClient for automatic SQL span creation
        JsonObject jdbcConfig = new JsonObject()
                .put("url", "jdbc:postgresql://" +
                        getEnvOrDefault("POSTGRES_HOST", "localhost") + ":" +
                        getEnvOrDefault("POSTGRES_PORT", "5432") + "/" +
                        getEnvOrDefault("POSTGRES_DB", "holdingdb"))
                .put("driver_class", "org.postgresql.Driver")
                .put("user", getEnvOrDefault("POSTGRES_USER", "postgres"))
                .put("password", getEnvOrDefault("POSTGRES_PASSWORD", "postgres"))
                .put("max_pool_size", 5);

        JDBCClient rxJdbcClient = JDBCClient.createShared(vertx, jdbcConfig);
        SQLClient tracedSqlClient = TracedSQLClient.wrap(rxJdbcClient, "postgresql", "holdingdb");

        // Initialize repository and service with traced SQL client
        HoldingRepository repository = new HoldingRepository(tracedSqlClient);
        holdingService = new HoldingService(repository);

        // Plain WebClient — outbound calls use ClientTracing.inject() explicitly
        webClient = WebClient.create(vertx);

        // TracedWebClient — drop-in replacement that auto-injects traceparent
        tracedWebClient = TracedWebClient.create(vertx);

        pricingServiceUrl = getEnvOrDefault("PRICING_SERVICE_URL", "http://localhost:8081");

        // Create traced router for automatic HTTP server span creation
        Router router = TracedRouter.create(vertx);

        // Health check endpoint
        router.get("/health").handler(this::handleHealth);

        // Holding endpoints (SQL tracing via TracedSQLClient)
        router.get("/v1/holding").handler(this::handleGetAllHoldings);
        router.get("/v1/holding/:userId").handler(this::handleGetHoldingsByUser);
        router.post("/v1/holding").handler(this::handleCreateHolding);
        router.delete("/v1/holding/:id").handler(this::handleDeleteHolding);

        // Portfolio — uses ClientTracing.inject() for outbound calls
        router.get("/v1/portfolio/:userId").handler(this::handleGetPortfolio);

        // Portfolio — uses TracedWebClient for outbound calls
        router.get("/v1/portfolio-traced/:userId").handler(this::handleGetPortfolioTraced);

        // External public API calls — demonstrates outbound tracing to third-party services
        router.get("/v1/external/joke").handler(this::handleExternalJoke);
        router.get("/v1/external/post/:id").handler(this::handleExternalPost);

        int port = Integer.parseInt(getEnvOrDefault("APP_PORT", "8080"));

        // Initialize database schema and start server
        return repository.initializeSchema()
                .andThen(vertx.createHttpServer()
                        .requestHandler(router)
                        .rxListen(port)
                        .doOnSuccess(server -> logger.info("HTTP server started on port {}", port))
                        .ignoreElement());
    }

    private void handleHealth(RoutingContext ctx) {
        ctx.response()
                .putHeader("content-type", "application/json")
                .end(new JsonObject().put("status", "UP").encode());
    }

    private void handleGetAllHoldings(RoutingContext ctx) {
        holdingService.getAllHoldings()
                .subscribe(
                        holdings -> {
                            JsonArray result = new JsonArray();
                            holdings.forEach(h -> result.add(h.toJson()));
                            ctx.response()
                                    .putHeader("content-type", "application/json")
                                    .end(result.encode());
                        },
                        error -> handleError(ctx, error)
                );
    }

    private void handleGetHoldingsByUser(RoutingContext ctx) {
        String userId = ctx.pathParam("userId");
        holdingService.getHoldingsByUserId(userId)
                .subscribe(
                        holdings -> {
                            JsonArray result = new JsonArray();
                            holdings.forEach(h -> result.add(h.toJson()));
                            ctx.response()
                                    .putHeader("content-type", "application/json")
                                    .end(result.encode());
                        },
                        error -> handleError(ctx, error)
                );
    }

    private void handleCreateHolding(RoutingContext ctx) {
        JsonObject body = ctx.getBodyAsJson();
        if (body == null) {
            ctx.response().setStatusCode(400)
                    .end(new JsonObject().put("error", "Invalid JSON body").encode());
            return;
        }

        Holding holding = new Holding(
                null,
                body.getString("userId"),
                body.getString("symbol"),
                body.getInteger("quantity", 0)
        );

        holdingService.createHolding(holding)
                .subscribe(
                        created -> ctx.response()
                                .setStatusCode(201)
                                .putHeader("content-type", "application/json")
                                .end(created.toJson().encode()),
                        error -> handleError(ctx, error)
                );
    }

    private void handleDeleteHolding(RoutingContext ctx) {
        String id = ctx.pathParam("id");
        try {
            Long holdingId = Long.parseLong(id);
            holdingService.deleteHolding(holdingId)
                    .subscribe(
                            () -> ctx.response().setStatusCode(204).end(),
                            error -> handleError(ctx, error)
                    );
        } catch (NumberFormatException e) {
            ctx.response().setStatusCode(400)
                    .end(new JsonObject().put("error", "Invalid ID").encode());
        }
    }

    /**
     * Portfolio endpoint using ClientTracing.inject() — explicit per-request injection.
     * The traceparent header is injected into each outbound WebClient request manually.
     */
    private void handleGetPortfolio(RoutingContext ctx) {
        String userId = ctx.pathParam("userId");
        logger.info("Fetching portfolio for user: {} (ClientTracing.inject)", userId);

        holdingService.getHoldingsByUserId(userId)
                .flatMapObservable(holdings -> io.reactivex.Observable.fromIterable(holdings))
                .flatMapSingle(holding ->
                        // ClientTracing.inject() wraps the request with traceparent header
                        ClientTracing.inject(
                                webClient.getAbs(pricingServiceUrl + "/v1/price/" + holding.getSymbol())
                        )
                                .rxSend()
                                .map(response -> {
                                    JsonObject priceData = response.bodyAsJsonObject();
                                    return holding.toJson()
                                            .put("currentPrice", priceData.getDouble("price", 0.0))
                                            .put("totalValue", holding.getQuantity() * priceData.getDouble("price", 0.0));
                                })
                                .onErrorReturnItem(holding.toJson()
                                        .put("currentPrice", 0.0)
                                        .put("totalValue", 0.0)
                                        .put("priceError", "Unable to fetch price"))
                )
                .toList()
                .subscribe(
                        portfolio -> {
                            JsonObject result = new JsonObject()
                                    .put("userId", userId)
                                    .put("holdings", new JsonArray(portfolio))
                                    .put("totalPortfolioValue", portfolio.stream()
                                            .mapToDouble(h -> h.getDouble("totalValue", 0.0))
                                            .sum());
                            ctx.response()
                                    .putHeader("content-type", "application/json")
                                    .end(result.encode());
                        },
                        error -> handleError(ctx, error)
                );
    }

    /**
     * Portfolio endpoint using TracedWebClient — automatic traceparent injection.
     * No per-request ClientTracing.inject() needed — the TracedWebClient handles it.
     */
    private void handleGetPortfolioTraced(RoutingContext ctx) {
        String userId = ctx.pathParam("userId");
        logger.info("Fetching portfolio for user: {} (TracedWebClient)", userId);

        holdingService.getHoldingsByUserId(userId)
                .flatMapObservable(holdings -> io.reactivex.Observable.fromIterable(holdings))
                .flatMapSingle(holding ->
                        // TracedWebClient auto-injects traceparent — no manual inject needed
                        tracedWebClient.getAbs(pricingServiceUrl + "/v1/price/" + holding.getSymbol())
                                .rxSend()
                                .map(response -> {
                                    JsonObject priceData = response.bodyAsJsonObject();
                                    return holding.toJson()
                                            .put("currentPrice", priceData.getDouble("price", 0.0))
                                            .put("totalValue", holding.getQuantity() * priceData.getDouble("price", 0.0));
                                })
                                .onErrorReturnItem(holding.toJson()
                                        .put("currentPrice", 0.0)
                                        .put("totalValue", 0.0)
                                        .put("priceError", "Unable to fetch price"))
                )
                .toList()
                .subscribe(
                        portfolio -> {
                            JsonObject result = new JsonObject()
                                    .put("userId", userId)
                                    .put("holdings", new JsonArray(portfolio))
                                    .put("totalPortfolioValue", portfolio.stream()
                                            .mapToDouble(h -> h.getDouble("totalValue", 0.0))
                                            .sum());
                            ctx.response()
                                    .putHeader("content-type", "application/json")
                                    .end(result.encode());
                        },
                        error -> handleError(ctx, error)
                );
    }

    /**
     * External API call using ClientTracing.inject() — calls httpbin.org
     */
    private void handleExternalJoke(RoutingContext ctx) {
        logger.info("Fetching from external API (ClientTracing.inject)");

        ClientTracing.inject(
                webClient.getAbs("https://httpbin.org/get")
                        .addQueryParam("source", "holding-service")
        )
                .rxSend()
                .subscribe(
                        response -> ctx.response()
                                .putHeader("content-type", "application/json")
                                .end(new JsonObject()
                                        .put("source", "httpbin.org")
                                        .put("status", response.statusCode())
                                        .put("method", "ClientTracing.inject")
                                        .encode()),
                        error -> handleError(ctx, error)
                );
    }

    /**
     * External API call using TracedWebClient — calls jsonplaceholder
     */
    private void handleExternalPost(RoutingContext ctx) {
        String postId = ctx.pathParam("id");
        logger.info("Fetching external post {} (TracedWebClient)", postId);

        tracedWebClient.getAbs("https://jsonplaceholder.typicode.com/posts/" + postId)
                .rxSend()
                .subscribe(
                        response -> {
                            JsonObject post = response.bodyAsJsonObject();
                            ctx.response()
                                    .putHeader("content-type", "application/json")
                                    .end(new JsonObject()
                                            .put("source", "jsonplaceholder.typicode.com")
                                            .put("method", "TracedWebClient")
                                            .put("post", post)
                                            .encode());
                        },
                        error -> handleError(ctx, error)
                );
    }

    private void handleError(RoutingContext ctx, Throwable error) {
        logger.error("Request failed", error);
        ctx.response()
                .setStatusCode(500)
                .putHeader("content-type", "application/json")
                .end(new JsonObject().put("error", error.getMessage()).encode());
    }

    private String getEnvOrDefault(String name, String defaultValue) {
        String value = System.getenv(name);
        return value != null ? value : defaultValue;
    }
}
