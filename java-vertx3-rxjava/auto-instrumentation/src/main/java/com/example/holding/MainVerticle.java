package com.example.holding;

import com.aerospike.client.AerospikeClient;
import com.aerospike.client.Bin;
import com.aerospike.client.IAerospikeClient;
import com.aerospike.client.Key;
import com.aerospike.client.Record;
import com.aerospike.client.policy.ClientPolicy;
import com.example.holding.model.Holding;
import com.example.holding.repository.HoldingRepository;
import com.example.holding.service.HoldingService;
import io.last9.tracing.otel.v3.ClientTracing;
import io.last9.tracing.otel.v3.KafkaTracing;
import io.last9.tracing.otel.v3.TracedAerospikeClient;
import io.last9.tracing.otel.v3.TracedRouter;
import io.last9.tracing.otel.v3.TracedSQLClient;
import io.last9.tracing.otel.v3.TracedWebClient;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Context;
import io.opentelemetry.context.Scope;
import io.opentelemetry.semconv.SemanticAttributes;
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
import io.vertx.reactivex.kafka.client.consumer.KafkaConsumer;
import io.vertx.reactivex.kafka.client.producer.KafkaProducer;
import io.vertx.reactivex.kafka.client.producer.KafkaProducerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.Map;

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
    private KafkaProducer<String, String> kafkaProducer;
    private String kafkaTopic;
    private IAerospikeClient aerospikeClient;
    private String aerospikeNamespace;

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

        // Initialize Kafka producer with tracing
        kafkaTopic = getEnvOrDefault("KAFKA_TOPIC", "holding-events");
        Map<String, String> kafkaConfig = new HashMap<>();
        kafkaConfig.put("bootstrap.servers", getEnvOrDefault("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"));
        kafkaConfig.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        kafkaConfig.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        kafkaConfig.put("acks", "1");
        kafkaProducer = KafkaProducer.create(vertx, kafkaConfig);

        // Initialize Kafka consumer with traced batch handler
        Map<String, String> consumerConfig = new HashMap<>();
        consumerConfig.put("bootstrap.servers", getEnvOrDefault("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"));
        consumerConfig.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
        consumerConfig.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
        consumerConfig.put("group.id", "holding-service-consumer");
        consumerConfig.put("auto.offset.reset", "earliest");
        consumerConfig.put("enable.auto.commit", "true");

        KafkaConsumer<String, String> kafkaConsumer = KafkaConsumer.create(vertx, consumerConfig);
        // KafkaTracing works with core Vert.x types — use getDelegate() for the batch handler
        kafkaConsumer.getDelegate().batchHandler(KafkaTracing.tracedBatchHandler(kafkaTopic, records -> {
            logger.info("Consumed batch of {} records from topic '{}'", records.size(), kafkaTopic);
            for (int i = 0; i < records.size(); i++) {
                logger.info("  Record: key={}, value={}", records.recordAt(i).key(), records.recordAt(i).value());
            }
        }));
        kafkaConsumer.subscribe(kafkaTopic);

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

        // Kafka endpoints — demonstrates KafkaTracing for producer/consumer spans
        router.post("/v1/kafka/produce").handler(this::handleKafkaProduce);
        router.post("/v1/kafka/produce-batch").handler(this::handleKafkaProduceBatch);

        // Aerospike endpoints — demonstrates TracedAerospikeClient for cache spans
        router.post("/v1/cache/:key").handler(this::handleCachePut);
        router.get("/v1/cache/:key").handler(this::handleCacheGet);
        router.delete("/v1/cache/:key").handler(this::handleCacheDelete);

        // Complex multi-system endpoint — DB + Aerospike + Kafka + outbound HTTP
        router.get("/v1/portfolio-full/:userId").handler(this::handleFullPortfolio);

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

    // ---- Kafka Handlers ----

    /**
     * Produce a single message to Kafka. Wraps with a PRODUCER span manually since
     * Vert.x 3 Kafka client has no built-in OTel instrumentation.
     */
    private void handleKafkaProduce(RoutingContext ctx) {
        JsonObject body = ctx.getBodyAsJson();
        String key = body != null ? body.getString("key", "default") : "default";
        String value = body != null ? body.getString("value", "{}") : "{}";

        logger.info("Producing to Kafka topic '{}': key={}", kafkaTopic, key);

        KafkaProducerRecord<String, String> record =
                KafkaProducerRecord.create(kafkaTopic, key, value);

        tracedKafkaSend(record)
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
     * Produce multiple messages to Kafka. Each send is wrapped with a PRODUCER span.
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
                    return tracedKafkaSend(record);
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
     * Wraps a Kafka send with a PRODUCER span. Vert.x 3 has no Kafka tracing SPI,
     * so we create the span manually using OTel messaging semantic conventions.
     */
    private Single<io.vertx.kafka.client.producer.RecordMetadata> tracedKafkaSend(
            KafkaProducerRecord<String, String> record) {
        Tracer tracer = GlobalOpenTelemetry.get().getTracer("io.last9.tracing.otel.v3");
        Span span = tracer.spanBuilder(record.topic() + " publish")
                .setSpanKind(SpanKind.PRODUCER)
                .setAttribute(SemanticAttributes.MESSAGING_SYSTEM, "kafka")
                .setAttribute(SemanticAttributes.MESSAGING_DESTINATION_NAME, record.topic())
                .setAttribute(SemanticAttributes.MESSAGING_OPERATION, "publish")
                .startSpan();

        if (record.key() != null) {
            span.setAttribute(SemanticAttributes.MESSAGING_KAFKA_MESSAGE_KEY, record.key());
        }

        return kafkaProducer.rxSend(record)
                .doOnSuccess(metadata -> {
                    span.setAttribute(SemanticAttributes.MESSAGING_KAFKA_DESTINATION_PARTITION,
                            (long) metadata.getPartition());
                    span.setAttribute(SemanticAttributes.MESSAGING_KAFKA_MESSAGE_OFFSET,
                            metadata.getOffset());
                    span.end();
                })
                .doOnError(err -> {
                    span.recordException(err);
                    span.setStatus(StatusCode.ERROR, err.getMessage());
                    span.end();
                });
    }

    // ---- Aerospike Cache Handlers ----

    /**
     * Put a value into Aerospike cache. Demonstrates TracedAerospikeClient PUT span.
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

        // Capture OTel context from event loop — worker thread has no context
        Context otelCtx = Context.current();
        vertx.<String>rxExecuteBlocking(promise -> {
            try (Scope ignored = otelCtx.makeCurrent()) {
                Key asKey = new Key(aerospikeNamespace, "cache", cacheKey);
                Bin valueBin = new Bin("data", body.encode());
                Bin timestampBin = new Bin("updated", System.currentTimeMillis());
                aerospikeClient.put(null, asKey, valueBin, timestampBin);
                promise.complete("ok");
            } catch (Exception e) {
                promise.fail(e);
            }
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
     * Get a value from Aerospike cache. Demonstrates TracedAerospikeClient GET span.
     */
    private void handleCacheGet(RoutingContext ctx) {
        String cacheKey = ctx.pathParam("key");

        if (aerospikeClient == null) {
            ctx.response().setStatusCode(503)
                    .end(new JsonObject().put("error", "Aerospike not available").encode());
            return;
        }

        Context otelCtx = Context.current();
        vertx.<JsonObject>rxExecuteBlocking(promise -> {
            try (Scope ignored = otelCtx.makeCurrent()) {
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
            } catch (Exception e) {
                promise.fail(e);
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
     * Delete a value from Aerospike cache. Demonstrates TracedAerospikeClient DELETE span.
     */
    private void handleCacheDelete(RoutingContext ctx) {
        String cacheKey = ctx.pathParam("key");

        if (aerospikeClient == null) {
            ctx.response().setStatusCode(503)
                    .end(new JsonObject().put("error", "Aerospike not available").encode());
            return;
        }

        Context otelCtx = Context.current();
        vertx.<Boolean>rxExecuteBlocking(promise -> {
            try (Scope ignored = otelCtx.makeCurrent()) {
                Key asKey = new Key(aerospikeNamespace, "cache", cacheKey);
                boolean deleted = aerospikeClient.delete(null, asKey);
                promise.complete(deleted);
            } catch (Exception e) {
                promise.fail(e);
            }
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
                    // Check Aerospike cache first, fall back to pricing service
                    String cacheKey = "price:" + holding.getSymbol();
                    // Capture OTel context for the worker thread
                    Context otelCtx = Context.current();
                    return vertx.<JsonObject>rxExecuteBlocking(promise -> {
                        try (Scope ignored = otelCtx.makeCurrent()) {
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
                        } catch (Exception e) {
                            promise.complete(new JsonObject().put("_miss", true));
                        }
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

                    // Publish portfolio event to Kafka
                    JsonObject event = new JsonObject()
                            .put("type", "portfolio_viewed")
                            .put("userId", userId)
                            .put("totalValue", total)
                            .put("holdingCount", portfolio.size())
                            .put("timestamp", System.currentTimeMillis());

                    KafkaProducerRecord<String, String> record =
                            KafkaProducerRecord.create(kafkaTopic, userId, event.encode());

                    double finalTotal = total;
                    return tracedKafkaSend(record)
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
