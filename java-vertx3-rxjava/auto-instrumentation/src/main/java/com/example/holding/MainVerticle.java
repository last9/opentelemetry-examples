package com.example.holding;

import com.aerospike.client.AerospikeClient;
import com.aerospike.client.Bin;
import com.aerospike.client.Key;
import com.aerospike.client.Record;
import com.aerospike.client.policy.ClientPolicy;
import com.example.holding.model.Holding;
import com.example.holding.repository.HoldingRepository;
import com.example.holding.service.HoldingService;
import io.last9.tracing.otel.v3.ClientTracing;
import io.last9.tracing.otel.v3.KafkaTracing;
import io.last9.tracing.otel.v3.TracedAerospikeClient;
import io.last9.tracing.otel.v3.TracedKafkaProducer;
import io.last9.tracing.otel.v3.TracedMySQLClient;
import io.last9.tracing.otel.v3.TracedRouter;
import io.last9.tracing.otel.v3.TracedSQLClient;
import io.last9.tracing.otel.v3.TracedVertx;
import io.last9.tracing.otel.v3.TracedWebClient;
import io.vertx.reactivex.mysqlclient.MySQLPool;
import io.vertx.mysqlclient.MySQLConnectOptions;
import io.vertx.sqlclient.PoolOptions;
import io.vertx.reactivex.kafka.client.consumer.KafkaConsumer;
import io.reactivex.Completable;
import io.reactivex.Single;
import io.vertx.core.json.JsonArray;
import io.vertx.core.json.JsonObject;
import io.vertx.reactivex.core.AbstractVerticle;
import io.vertx.reactivex.ext.jdbc.JDBCClient;
import io.vertx.reactivex.ext.sql.SQLClient;
import io.vertx.reactivex.ext.web.Router;
import io.vertx.reactivex.ext.web.RoutingContext;
import io.vertx.reactivex.ext.web.client.WebClient;
import io.vertx.reactivex.kafka.client.producer.KafkaProducer;
import io.vertx.reactivex.kafka.client.producer.KafkaProducerRecord;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.Map;

/**
 * Main Verticle for the Holding Service.
 * Demonstrates Vert.x 3 with RxJava2 and automatic OpenTelemetry instrumentation.
 *
 * Tracing features used:
 * - TracedRouter:          automatic SERVER spans for every inbound HTTP request
 * - TracedSQLClient:       automatic CLIENT spans for every SQL query
 * - TracedWebClient:       drop-in WebClient with automatic CLIENT spans + traceparent
 * - ClientTracing:         manual traceparent injection for outbound WebClient requests
 * - TracedKafkaProducer:   automatic PRODUCER spans for Kafka sends + header propagation
 * - KafkaTracing.setupConsumer(): wire CONSUMER + ERROR spans on an existing KafkaConsumer
 * - TracedAerospikeClient: automatic CLIENT spans for Aerospike operations
 * - TracedVertx:           OTel context propagation to worker threads
 */
public class MainVerticle extends AbstractVerticle {

    private static final Logger logger = LoggerFactory.getLogger(MainVerticle.class);

    private HoldingService holdingService;
    private WebClient webClient;
    private WebClient tracedWebClient;
    private String pricingServiceUrl;
    private TracedKafkaProducer<String, String> tracedKafkaProducer;
    private String kafkaTopic;
    private TracedAerospikeClient aerospikeClient;
    private String aerospikeNamespace;
    private TracedMySQLClient mysqlClient;

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

        // Initialize Kafka producer wrapped with TracedKafkaProducer for automatic PRODUCER spans
        kafkaTopic = getEnvOrDefault("KAFKA_TOPIC", "holding-events");
        Map<String, String> kafkaConfig = new HashMap<>();
        kafkaConfig.put("bootstrap.servers", getEnvOrDefault("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"));
        kafkaConfig.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        kafkaConfig.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        kafkaConfig.put("acks", "1");
        tracedKafkaProducer = TracedKafkaProducer.wrap(KafkaProducer.create(vertx, kafkaConfig));

        // Initialize Kafka consumer using KafkaTracing.setupConsumer() — wires batch handler,
        // exception handler (ERROR spans for broker/auth/deserialization errors), no-op per-record
        // handler (required by Vert.x to start polling), and subscribe — all in one call.
        String consumerGroup = "holding-service-consumer";
        Map<String, String> consumerConfig = new HashMap<>();
        consumerConfig.put("bootstrap.servers", getEnvOrDefault("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"));
        consumerConfig.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
        consumerConfig.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
        consumerConfig.put("group.id", consumerGroup);
        consumerConfig.put("auto.offset.reset", "earliest");
        consumerConfig.put("enable.auto.commit", "true");

        KafkaConsumer<String, String> consumer = KafkaConsumer.create(vertx, consumerConfig);
        KafkaTracing.setupConsumer(consumer, kafkaTopic, consumerGroup, records -> {
            logger.info("Consumed batch of {} records from topic '{}'", records.size(), kafkaTopic);
            for (int i = 0; i < records.size(); i++) {
                var rec = records.recordAt(i);
                if (rec.value() == null) {
                    // Tombstone record — value is null, indicates deletion
                    logger.info("  Tombstone record: key={}", rec.key());
                } else if (rec.value() != null && rec.value().startsWith("__poison__")) {
                    // Poison-pill record — deliberately throw to demonstrate exception recording
                    // on the CONSUMER span. KafkaTracing.tracedBatchHandler catches this and
                    // calls span.recordException() + span.setStatus(ERROR).
                    throw new RuntimeException("Poison-pill message detected: key=" + rec.key()
                            + ", value=" + rec.value());
                } else {
                    logger.info("  Record: key={}, value={}", rec.key(), rec.value());
                }
            }

            // Process the batch: cache in Aerospike + outbound HTTP enrichment
            // Both produce child CLIENT spans under the CONSUMER span
            if (records.size() > 0) {
                String lastKey = String.valueOf(records.recordAt(records.size() - 1).key());
                String lastValue = String.valueOf(records.recordAt(records.size() - 1).value());

                // Aerospike cache via TracedVertx (worker thread, preserves OTel context)
                if (aerospikeClient != null) {
                    TracedVertx.<String>rxExecuteBlocking(vertx, promise -> {
                        Key asKey = new Key(aerospikeNamespace, "events", "evt:" + lastKey);
                        aerospikeClient.put(null, asKey, new Bin("data", lastValue != null ? lastValue : ""),
                                new Bin("consumed_at", System.currentTimeMillis()));
                        logger.info("Cached consumed event: evt:{}", lastKey);
                        promise.complete("ok");
                    }).subscribe(v -> {}, err -> logger.warn("Cache failed: {}", err.getMessage()));
                }

                // Outbound HTTP enrichment via TracedWebClient (CLIENT span)
                tracedWebClient.getAbs(pricingServiceUrl + "/v1/price/AAPL")
                        .rxSend()
                        .subscribe(
                                resp -> logger.info("Consumer enrichment: status={}", resp.statusCode()),
                                err -> logger.debug("Enrichment failed: {}", err.getMessage()));
            }
        });

        // Initialize Aerospike with TracedAerospikeClient
        aerospikeNamespace = getEnvOrDefault("AEROSPIKE_NAMESPACE", "test");
        String aerospikeHost = getEnvOrDefault("AEROSPIKE_HOST", "localhost");
        int aerospikePort = Integer.parseInt(getEnvOrDefault("AEROSPIKE_PORT", "3000"));
        try {
            ClientPolicy policy = new ClientPolicy();
            policy.timeout = 5000;
            policy.failIfNotConnected = false;
            AerospikeClient rawClient = new AerospikeClient(policy, aerospikeHost, aerospikePort);
            aerospikeClient = TracedAerospikeClient.wrap(rawClient, aerospikeNamespace);
            logger.info("Aerospike client connected to {}:{}", aerospikeHost, aerospikePort);
        } catch (Exception e) {
            logger.warn("Aerospike not available — cache endpoints will return errors: {}", e.getMessage());
        }

        // Initialize MySQL reactive pool with TracedMySQLClient for automatic CLIENT spans
        try {
            MySQLConnectOptions mysqlOptions = new MySQLConnectOptions()
                    .setHost(getEnvOrDefault("MYSQL_HOST", "localhost"))
                    .setPort(Integer.parseInt(getEnvOrDefault("MYSQL_PORT", "3306")))
                    .setDatabase(getEnvOrDefault("MYSQL_DB", "testdb"))
                    .setUser(getEnvOrDefault("MYSQL_USER", "root"))
                    .setPassword(getEnvOrDefault("MYSQL_PASSWORD", "root"));
            PoolOptions poolOptions = new PoolOptions().setMaxSize(5);
            MySQLPool pool = MySQLPool.pool(vertx, mysqlOptions, poolOptions);
            mysqlClient = TracedMySQLClient.wrap(pool, getEnvOrDefault("MYSQL_DB", "testdb"));
            logger.info("MySQL pool created ({}:{})", getEnvOrDefault("MYSQL_HOST", "localhost"),
                    getEnvOrDefault("MYSQL_PORT", "3306"));
        } catch (Exception e) {
            logger.warn("MySQL not available — /v1/mysql/* endpoints will return errors: {}", e.getMessage());
        }

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

        // Kafka endpoints — demonstrates TracedKafkaProducer for automatic PRODUCER spans
        router.post("/v1/kafka/produce").handler(this::handleKafkaProduce);
        router.post("/v1/kafka/produce-batch").handler(this::handleKafkaProduceBatch);
        // Tombstone endpoint — null-value record signals downstream consumers to delete a key
        router.delete("/v1/kafka/tombstone/:key").handler(this::handleKafkaTombstone);

        // Aerospike endpoints — demonstrates TracedAerospikeClient + TracedVertx
        router.post("/v1/cache/:key").handler(this::handleCachePut);
        router.get("/v1/cache/:key").handler(this::handleCacheGet);
        router.delete("/v1/cache/:key").handler(this::handleCacheDelete);

        // MySQL reactive client endpoints — demonstrates TracedMySQLClient CLIENT spans
        router.get("/v1/mysql/ping").handler(this::handleMySQLPing);
        router.get("/v1/mysql/query").handler(this::handleMySQLQuery);

        // Complex multi-system endpoint — DB + Aerospike + Kafka + outbound HTTP
        router.get("/v1/portfolio-full/:userId").handler(this::handleFullPortfolio);

        // Exception scenario endpoints — demonstrate exception recording on spans
        // /v1/error/http   — calls ctx.fail(throwable) so TracedRouter records the exception event
        // /v1/error/try-catch — catches exception manually and records it via Span.current()
        router.get("/v1/error/http").handler(this::handleErrorHttp);
        router.get("/v1/error/try-catch").handler(this::handleErrorTryCatch);

        // Global failure handler — handles ctx.fail(throwable) from any route.
        // TracedRouter's headersEndHandler fires when this sends the response, picks up
        // ctx.failure(), and calls span.recordException() so the exception appears in traces.
        router.route().failureHandler(ctx -> {
            int status = ctx.statusCode() > 0 ? ctx.statusCode() : 500;
            Throwable failure = ctx.failure();
            String message = failure != null ? failure.getMessage() : "Internal Server Error";
            logger.error("Failure handler: status={}, error={}", status, message, failure);
            ctx.response()
                    .setStatusCode(status)
                    .putHeader("content-type", "application/json")
                    .end(new JsonObject().put("error", message).encode());
        });

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

        ClientTracing.traced(
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

    // ---- Kafka Handlers ----

    /**
     * Produce a single message to Kafka.
     * TracedKafkaProducer automatically creates a PRODUCER span with OTel messaging
     * semantic conventions and injects traceparent into Kafka headers.
     */
    private void handleKafkaProduce(RoutingContext ctx) {
        JsonObject body = ctx.getBodyAsJson();
        String key = body != null ? body.getString("key", "default") : "default";
        String value = body != null ? body.getString("value", "{}") : "{}";

        logger.info("Producing to Kafka topic '{}': key={}", kafkaTopic, key);

        KafkaProducerRecord<String, String> record =
                KafkaProducerRecord.create(kafkaTopic, key, value);

        tracedKafkaProducer.rxSend(record)
                .subscribe(
                        metadata -> ctx.response()
                                .putHeader("content-type", "application/json")
                                .end(new JsonObject()
                                        .put("status", "produced")
                                        .put("topic", kafkaTopic)
                                        .put("partition", metadata.getPartition())
                                        .put("offset", metadata.getOffset())
                                        .encode()),
                        error -> handleError(ctx, error)
                );
    }

    /**
     * Produce multiple messages to Kafka. Each send automatically gets a PRODUCER span.
     */
    private void handleKafkaProduceBatch(RoutingContext ctx) {
        JsonObject body = ctx.getBodyAsJson();
        int count = body != null ? body.getInteger("count", 5) : 5;
        String prefix = body != null ? body.getString("prefix", "event") : "event";

        logger.info("Producing {} messages to Kafka topic '{}'", count, kafkaTopic);

        io.reactivex.Observable.range(1, count)
                .flatMapSingle(i -> {
                    JsonObject event = new JsonObject()
                            .put("type", prefix)
                            .put("index", i)
                            .put("timestamp", System.currentTimeMillis());
                    KafkaProducerRecord<String, String> record =
                            KafkaProducerRecord.create(kafkaTopic, prefix + "-" + i, event.encode());
                    return tracedKafkaProducer.rxSend(record);
                })
                .toList()
                .subscribe(
                        results -> ctx.response()
                                .putHeader("content-type", "application/json")
                                .end(new JsonObject()
                                        .put("status", "produced")
                                        .put("count", results.size())
                                        .put("topic", kafkaTopic)
                                        .encode()),
                        error -> handleError(ctx, error)
                );
    }

    /**
     * Send a Kafka tombstone (null-value record) for the given key.
     * Tombstones signal downstream consumers to delete the record associated with that key.
     * The PRODUCER span sets {@code messaging.kafka.message.tombstone = true}.
     */
    private void handleKafkaTombstone(RoutingContext ctx) {
        String key = ctx.pathParam("key");
        logger.info("Sending Kafka tombstone for key '{}' on topic '{}'", key, kafkaTopic);

        // Null value = tombstone — KafkaTracing sets messaging.kafka.message.tombstone = true on the span
        KafkaProducerRecord<String, String> record =
                KafkaProducerRecord.create(kafkaTopic, key, null);

        tracedKafkaProducer.rxSend(record)
                .subscribe(
                        metadata -> ctx.response()
                                .putHeader("content-type", "application/json")
                                .end(new JsonObject()
                                        .put("status", "tombstone_sent")
                                        .put("topic", kafkaTopic)
                                        .put("key", key)
                                        .put("partition", metadata.getPartition())
                                        .put("offset", metadata.getOffset())
                                        .encode()),
                        error -> handleError(ctx, error)
                );
    }

    // ---- Aerospike Cache Handlers ----

    /**
     * Put a value into Aerospike cache.
     * TracedVertx propagates OTel context to the worker thread so TracedAerospikeClient
     * creates spans that parent under the current SERVER span.
     */
    private void handleCachePut(RoutingContext ctx) {
        String cacheKey = ctx.pathParam("key");
        JsonObject body = ctx.getBodyAsJson();
        if (body == null) {
            ctx.response().setStatusCode(400)
                    .end(new JsonObject().put("error", "Invalid JSON body").encode());
            return;
        }

        if (aerospikeClient == null) {
            ctx.response().setStatusCode(503)
                    .end(new JsonObject().put("error", "Aerospike not available").encode());
            return;
        }

        TracedVertx.<String>rxExecuteBlocking(vertx, promise -> {
            Key asKey = new Key(aerospikeNamespace, "cache", cacheKey);
            Bin valueBin = new Bin("data", body.encode());
            Bin timestampBin = new Bin("updated", System.currentTimeMillis());
            aerospikeClient.put(null, asKey, valueBin, timestampBin);
            promise.complete("ok");
        }).toSingle()
                .subscribe(
                        v -> ctx.response()
                                .putHeader("content-type", "application/json")
                                .end(new JsonObject()
                                        .put("status", "cached")
                                        .put("key", cacheKey)
                                        .encode()),
                        error -> handleError(ctx, error)
                );
    }

    /**
     * Get a value from Aerospike cache.
     * TracedVertx propagates OTel context to the worker thread.
     */
    private void handleCacheGet(RoutingContext ctx) {
        String cacheKey = ctx.pathParam("key");

        if (aerospikeClient == null) {
            ctx.response().setStatusCode(503)
                    .end(new JsonObject().put("error", "Aerospike not available").encode());
            return;
        }

        TracedVertx.<JsonObject>rxExecuteBlocking(vertx, promise -> {
            Key asKey = new Key(aerospikeNamespace, "cache", cacheKey);
            Record record = aerospikeClient.get(null, asKey);
            if (record != null) {
                String data = record.getString("data");
                promise.complete(new JsonObject()
                        .put("key", cacheKey)
                        .put("data", new JsonObject(data))
                        .put("generation", record.generation)
                        .put("expiration", record.expiration));
            } else {
                promise.complete(new JsonObject().put("_notFound", true));
            }
        }).toSingle()
                .subscribe(
                        result -> {
                            if (!result.containsKey("_notFound")) {
                                ctx.response()
                                        .putHeader("content-type", "application/json")
                                        .end(result.encode());
                            } else {
                                ctx.response().setStatusCode(404)
                                        .end(new JsonObject().put("error", "Key not found").encode());
                            }
                        },
                        error -> handleError(ctx, error)
                );
    }

    /**
     * Delete a value from Aerospike cache.
     * TracedVertx propagates OTel context to the worker thread.
     */
    private void handleCacheDelete(RoutingContext ctx) {
        String cacheKey = ctx.pathParam("key");

        if (aerospikeClient == null) {
            ctx.response().setStatusCode(503)
                    .end(new JsonObject().put("error", "Aerospike not available").encode());
            return;
        }

        TracedVertx.<Boolean>rxExecuteBlocking(vertx, promise -> {
            Key asKey = new Key(aerospikeNamespace, "cache", cacheKey);
            boolean deleted = aerospikeClient.delete(null, asKey);
            promise.complete(deleted);
        }).toSingle()
                .subscribe(
                        deleted -> ctx.response()
                                .putHeader("content-type", "application/json")
                                .end(new JsonObject()
                                        .put("status", deleted ? "deleted" : "not_found")
                                        .put("key", cacheKey)
                                        .encode()),
                        error -> handleError(ctx, error)
                );
    }

    // ---- MySQL Handlers ----

    /**
     * Runs a MySQL ping (SELECT 1) and returns the server time.
     * TracedMySQLClient produces a CLIENT span for the query.
     */
    private void handleMySQLPing(RoutingContext ctx) {
        if (mysqlClient == null) {
            ctx.response().setStatusCode(503)
                    .end(new JsonObject().put("error", "MySQL not available").encode());
            return;
        }

        mysqlClient.query("SELECT 1 AS alive, NOW() AS server_time")
                .subscribe(
                        rows -> {
                            io.vertx.reactivex.sqlclient.Row row = rows.iterator().next();
                            ctx.response()
                                    .putHeader("content-type", "application/json")
                                    .end(new JsonObject()
                                            .put("alive", row.getInteger("alive"))
                                            .put("server_time", String.valueOf(row.getValue("server_time")))
                                            .encode());
                        },
                        error -> handleError(ctx, error)
                );
    }

    /**
     * Runs an arbitrary MySQL query passed as ?sql=... query param.
     * Falls back to SHOW TABLES if no query is supplied.
     * TracedMySQLClient produces a CLIENT span.
     */
    private void handleMySQLQuery(RoutingContext ctx) {
        if (mysqlClient == null) {
            ctx.response().setStatusCode(503)
                    .end(new JsonObject().put("error", "MySQL not available").encode());
            return;
        }

        String sql = ctx.request().getParam("sql");
        if (sql == null || sql.isBlank()) {
            sql = "SHOW TABLES";
        }
        String finalSql = sql;

        mysqlClient.query(finalSql)
                .subscribe(
                        rows -> {
                            io.vertx.core.json.JsonArray results = new io.vertx.core.json.JsonArray();
                            rows.forEach(row -> {
                                io.vertx.core.json.JsonObject obj = new io.vertx.core.json.JsonObject();
                                for (int i = 0; i < row.size(); i++) {
                                    obj.put(String.valueOf(i), String.valueOf(row.getValue(i)));
                                }
                                results.add(obj);
                            });
                            ctx.response()
                                    .putHeader("content-type", "application/json")
                                    .end(new JsonObject()
                                            .put("sql", finalSql)
                                            .put("rows", results.size())
                                            .put("results", results)
                                            .encode());
                        },
                        error -> handleError(ctx, error)
                );
    }

    // ---- Complex Multi-System Handler ----

    /**
     * Full portfolio endpoint: DB query + Aerospike cache + outbound HTTP pricing + Kafka event.
     * Produces a rich trace spanning SQL, Aerospike, HTTP CLIENT, and Kafka PRODUCER spans.
     */
    private void handleFullPortfolio(RoutingContext ctx) {
        String userId = ctx.pathParam("userId");
        logger.info("Full portfolio for user: {} (DB + Cache + HTTP + Kafka)", userId);

        holdingService.getHoldingsByUserId(userId)
                .flatMapObservable(holdings -> io.reactivex.Observable.fromIterable(holdings))
                .flatMapSingle(holding -> {
                    String cacheKey = "price:" + holding.getSymbol();
                    // TracedVertx propagates OTel context to the worker thread
                    return TracedVertx.<JsonObject>rxExecuteBlocking(vertx, promise -> {
                        if (aerospikeClient != null) {
                            Key asKey = new Key(aerospikeNamespace, "cache", cacheKey);
                            Record cached = aerospikeClient.get(null, asKey);
                            if (cached != null) {
                                promise.complete(new JsonObject(cached.getString("data"))
                                        .put("source", "cache"));
                                return;
                            }
                        }
                        promise.complete(new JsonObject().put("_miss", true));
                    }).toSingle()
                            .flatMap(cached -> {
                                if (!cached.containsKey("_miss")) {
                                    return Single.just(cached);
                                }
                                // Cache miss — call pricing service via TracedWebClient
                                return tracedWebClient
                                        .getAbs(pricingServiceUrl + "/v1/price/" + holding.getSymbol())
                                        .rxSend()
                                        .map(response -> {
                                            JsonObject priceData = response.bodyAsJsonObject();
                                            // Cache the price in Aerospike
                                            if (aerospikeClient != null) {
                                                try {
                                                    Key asKey = new Key(aerospikeNamespace, "cache", cacheKey);
                                                    Bin valueBin = new Bin("data", priceData.encode());
                                                    aerospikeClient.put(null, asKey, valueBin);
                                                } catch (Exception e) {
                                                    logger.warn("Failed to cache price: {}", e.getMessage());
                                                }
                                            }
                                            return priceData.put("source", "api");
                                        });
                            })
                            .map(priceData -> holding.toJson()
                                    .put("currentPrice", priceData.getDouble("price", 0.0))
                                    .put("totalValue", holding.getQuantity() * priceData.getDouble("price", 0.0))
                                    .put("priceSource", priceData.getString("source", "unknown")))
                            .onErrorReturnItem(holding.toJson()
                                    .put("currentPrice", 0.0)
                                    .put("totalValue", 0.0)
                                    .put("priceError", "Unable to fetch price"));
                })
                .toList()
                .flatMap(portfolio -> {
                    double total = 0;
                    JsonArray holdingsArray = new JsonArray();
                    for (Object item : portfolio) {
                        JsonObject h = (JsonObject) item;
                        holdingsArray.add(h);
                        total += h.getDouble("totalValue", 0.0);
                    }

                    // Publish portfolio event to Kafka via TracedKafkaProducer
                    JsonObject event = new JsonObject()
                            .put("type", "portfolio_viewed")
                            .put("userId", userId)
                            .put("totalValue", total)
                            .put("holdingCount", portfolio.size())
                            .put("timestamp", System.currentTimeMillis());

                    KafkaProducerRecord<String, String> record =
                            KafkaProducerRecord.create(kafkaTopic, userId, event.encode());

                    double finalTotal = total;
                    return tracedKafkaProducer.rxSend(record)
                            .map(metadata -> new JsonObject()
                                    .put("userId", userId)
                                    .put("holdings", holdingsArray)
                                    .put("totalPortfolioValue", finalTotal)
                                    .put("kafkaOffset", metadata.getOffset()));
                })
                .subscribe(
                        result -> ctx.response()
                                .putHeader("content-type", "application/json")
                                .end(result.encode()),
                        error -> handleError(ctx, error)
                );
    }

    /**
     * Intentional exception via ctx.fail(throwable).
     * TracedRouter's headersEndHandler picks up ctx.failure() and calls span.recordException(),
     * so the exception appears as a span event with exception.type, exception.message,
     * and exception.stacktrace in the observability platform.
     */
    private void handleErrorHttp(RoutingContext ctx) {
        String type = ctx.request().getParam("type");
        if (type == null) type = "runtime";
        try {
            if ("npe".equals(type)) {
                String s = null;
                s.length(); // deliberate NullPointerException
            } else if ("illegal".equals(type)) {
                throw new IllegalArgumentException("Simulated illegal argument: type=" + type);
            } else {
                throw new RuntimeException("Simulated runtime error for exception tracing demo");
            }
        } catch (Exception e) {
            logger.error("Simulated error (will appear as span exception event)", e);
            ctx.fail(e); // ← key: ctx.fail() sets ctx.failure(), picked up by TracedRouter
        }
    }

    /**
     * Manual try-catch with Span.current().recordException().
     * Shows how application code can record exceptions on the active span
     * even when not using ctx.fail() — e.g. inside business logic that
     * catches and recovers from errors but still wants observability.
     */
    private void handleErrorTryCatch(RoutingContext ctx) {
        Span span = Span.current();
        try {
            String divisor = ctx.request().getParam("divisor");
        if (divisor == null) divisor = "0";
            int result = 100 / Integer.parseInt(divisor); // ArithmeticException when divisor=0
            ctx.response()
                    .putHeader("content-type", "application/json")
                    .end(new JsonObject().put("result", result).encode());
        } catch (Exception e) {
            logger.error("Caught exception — recording on span manually", e);
            // Manually record on the active SERVER span so it shows up in traces
            span.recordException(e);
            span.setStatus(StatusCode.ERROR, e.getMessage());
            ctx.response()
                    .setStatusCode(500)
                    .putHeader("content-type", "application/json")
                    .end(new JsonObject().put("error", e.getMessage()).encode());
        }
    }

    private void handleError(RoutingContext ctx, Throwable error) {
        logger.error("Request failed", error);
        ctx.fail(500, error);
    }

    private String getEnvOrDefault(String name, String defaultValue) {
        String value = System.getenv(name);
        return value != null ? value : defaultValue;
    }
}
