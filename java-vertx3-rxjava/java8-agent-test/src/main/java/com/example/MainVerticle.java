package com.example;

import com.aerospike.client.AerospikeClient;
import com.aerospike.client.Bin;
import com.aerospike.client.Key;
import com.aerospike.client.Record;
import com.aerospike.client.policy.ClientPolicy;
import com.example.holding.model.Holding;
import com.example.holding.repository.HoldingRepository;
import com.example.holding.service.HoldingService;
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
import io.vertx.reactivex.mysqlclient.MySQLPool;
import io.vertx.mysqlclient.MySQLConnectOptions;
import io.vertx.sqlclient.PoolOptions;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.Map;

/**
 * Full Vert.x 3 + RxJava2 verticle compiled with Java 8 target.
 *
 * <p>Exercises every auto-instrumentation advice in vertx3-otel-agent:
 * <ul>
 *   <li>Router         — SERVER spans via RouterImplAdvice</li>
 *   <li>WebClient      — CLIENT spans + traceparent via WebClientAdvice</li>
 *   <li>JDBCClient     — CLIENT spans via JdbcClientAdvice</li>
 *   <li>KafkaProducer  — PRODUCER spans via KafkaProducerAdvice</li>
 *   <li>KafkaConsumer  — CONSUMER spans via KafkaConsumerAdvice</li>
 *   <li>AerospikeClient— CLIENT spans via AerospikeClientAdvice</li>
 *   <li>MySQLPool      — CLIENT spans via ReactiveSqlAdvice</li>
 * </ul>
 *
 * <p>IMPORTANT: All source code must be Java 8 compatible — no var, no isBlank(),
 * no Set.of()/Map.of(), no diamond-with-anonymous-class.
 */
public class MainVerticle extends AbstractVerticle {

    private static final Logger logger = LoggerFactory.getLogger(MainVerticle.class);

    private HoldingService holdingService;
    private WebClient webClient;
    private String pricingServiceUrl;
    private KafkaProducer<String, String> kafkaProducer;
    private String kafkaTopic;
    private AerospikeClient aerospikeClient;
    private String aerospikeNamespace;
    private MySQLPool mysqlPool;

    @Override
    public Completable rxStart() {
        logger.info("Starting MainVerticle (Java 8 agent test, zero-code tracing)...");
        logger.info("Java version: {}", System.getProperty("java.version"));
        logger.info("Class file version: {}", System.getProperty("java.class.version"));

        // ── PostgreSQL via JDBC ──────────────────────────────────────
        JsonObject jdbcConfig = new JsonObject()
                .put("url", "jdbc:postgresql://" +
                        getEnvOrDefault("POSTGRES_HOST", "localhost") + ":" +
                        getEnvOrDefault("POSTGRES_PORT", "5432") + "/" +
                        getEnvOrDefault("POSTGRES_DB", "holdingdb"))
                .put("driver_class", "org.postgresql.Driver")
                .put("user", getEnvOrDefault("POSTGRES_USER", "postgres"))
                .put("password", getEnvOrDefault("POSTGRES_PASSWORD", "postgres"))
                .put("max_pool_size", 5);

        SQLClient sqlClient = JDBCClient.createShared(vertx, jdbcConfig);
        HoldingRepository repository = new HoldingRepository(sqlClient);
        holdingService = new HoldingService(repository);

        // ── WebClient ────────────────────────────────────────────────
        webClient = WebClient.create(vertx);
        pricingServiceUrl = getEnvOrDefault("PRICING_SERVICE_URL", "http://localhost:8081");

        // ── Kafka Producer ───────────────────────────────────────────
        kafkaTopic = getEnvOrDefault("KAFKA_TOPIC", "holding-events");
        Map<String, String> kafkaConfig = new HashMap<String, String>();
        kafkaConfig.put("bootstrap.servers", getEnvOrDefault("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"));
        kafkaConfig.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        kafkaConfig.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        kafkaConfig.put("acks", "1");
        kafkaProducer = KafkaProducer.create(vertx, kafkaConfig);

        // ── Kafka Consumer ───────────────────────────────────────────
        Map<String, String> consumerConfig = new HashMap<String, String>();
        consumerConfig.put("bootstrap.servers", getEnvOrDefault("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"));
        consumerConfig.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
        consumerConfig.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
        consumerConfig.put("group.id", "java8-test-consumer");
        consumerConfig.put("auto.offset.reset", "earliest");
        consumerConfig.put("enable.auto.commit", "true");

        KafkaConsumer<String, String> consumer = KafkaConsumer.create(vertx, consumerConfig);
        consumer.handler(record -> {
            logger.info("Consumed record: key={}, value={}", record.key(), record.value());

            // Cache consumed event in Aerospike
            if (aerospikeClient != null) {
                vertx.<String>rxExecuteBlocking(promise -> {
                    Key asKey = new Key(aerospikeNamespace, "events", "evt:" + record.key());
                    aerospikeClient.put(null, asKey,
                            new Bin("data", record.value() != null ? record.value() : ""),
                            new Bin("consumed_at", System.currentTimeMillis()));
                    logger.info("Cached consumed event: evt:{}", record.key());
                    promise.complete("ok");
                }).subscribe(v -> {}, err -> logger.warn("Cache failed: {}", err.getMessage()));
            }

            // Outbound HTTP enrichment call
            webClient.getAbs(pricingServiceUrl + "/v1/price/AAPL")
                    .rxSend()
                    .subscribe(
                            resp -> logger.info("Consumer enrichment: status={}", resp.statusCode()),
                            err -> logger.debug("Enrichment failed: {}", err.getMessage()));
        });
        consumer.subscribe(kafkaTopic);

        // ── Aerospike ────────────────────────────────────────────────
        aerospikeNamespace = getEnvOrDefault("AEROSPIKE_NAMESPACE", "test");
        String aerospikeHost = getEnvOrDefault("AEROSPIKE_HOST", "localhost");
        int aerospikePort = Integer.parseInt(getEnvOrDefault("AEROSPIKE_PORT", "3000"));
        try {
            ClientPolicy policy = new ClientPolicy();
            policy.timeout = 5000;
            policy.failIfNotConnected = false;
            aerospikeClient = new AerospikeClient(policy, aerospikeHost, aerospikePort);
            logger.info("Aerospike client connected to {}:{}", aerospikeHost, aerospikePort);
        } catch (Exception e) {
            logger.warn("Aerospike not available — cache endpoints will return errors: {}", e.getMessage());
        }

        // ── MySQL reactive pool ──────────────────────────────────────
        try {
            MySQLConnectOptions mysqlOptions = new MySQLConnectOptions()
                    .setHost(getEnvOrDefault("MYSQL_HOST", "localhost"))
                    .setPort(Integer.parseInt(getEnvOrDefault("MYSQL_PORT", "3306")))
                    .setDatabase(getEnvOrDefault("MYSQL_DB", "testdb"))
                    .setUser(getEnvOrDefault("MYSQL_USER", "root"))
                    .setPassword(getEnvOrDefault("MYSQL_PASSWORD", "root"));
            PoolOptions poolOptions = new PoolOptions().setMaxSize(5);
            mysqlPool = MySQLPool.pool(vertx, mysqlOptions, poolOptions);
            logger.info("MySQL pool created ({}:{})",
                    getEnvOrDefault("MYSQL_HOST", "localhost"),
                    getEnvOrDefault("MYSQL_PORT", "3306"));
        } catch (Exception e) {
            logger.warn("MySQL not available — /v1/mysql/* endpoints will return errors: {}", e.getMessage());
        }

        // ── Router ───────────────────────────────────────────────────
        Router router = Router.router(vertx);

        // Health
        router.get("/health").handler(this::handleHealth);
        router.get("/ping").handler(ctx -> ctx.response()
                .putHeader("Content-Type", "text/plain").end("pong"));

        // Holding CRUD (JDBC — auto-traced by JdbcClientAdvice)
        router.get("/v1/holding").handler(this::handleGetAllHoldings);
        router.get("/v1/holding/:userId").handler(this::handleGetHoldingsByUser);
        router.post("/v1/holding")
                .handler(io.vertx.reactivex.ext.web.handler.BodyHandler.create())
                .handler(this::handleCreateHolding);
        router.delete("/v1/holding/:id").handler(this::handleDeleteHolding);

        // Portfolio (WebClient — auto-traced by WebClientAdvice)
        router.get("/v1/portfolio/:userId").handler(this::handleGetPortfolio);

        // External HTTP calls
        router.get("/v1/external/joke").handler(this::handleExternalJoke);
        router.get("/v1/external/post/:id").handler(this::handleExternalPost);

        // Kafka (auto-traced by KafkaProducerAdvice)
        router.post("/v1/kafka/produce")
                .handler(io.vertx.reactivex.ext.web.handler.BodyHandler.create())
                .handler(this::handleKafkaProduce);
        router.post("/v1/kafka/produce-batch")
                .handler(io.vertx.reactivex.ext.web.handler.BodyHandler.create())
                .handler(this::handleKafkaProduceBatch);

        // Aerospike cache (auto-traced by AerospikeClientAdvice)
        router.post("/v1/cache/:key")
                .handler(io.vertx.reactivex.ext.web.handler.BodyHandler.create())
                .handler(this::handleCachePut);
        router.get("/v1/cache/:key").handler(this::handleCacheGet);
        router.delete("/v1/cache/:key").handler(this::handleCacheDelete);

        // MySQL reactive (auto-traced by ReactiveSqlAdvice)
        router.get("/v1/mysql/ping").handler(this::handleMySQLPing);

        // Complex multi-system endpoint (DB + Aerospike + Kafka + outbound HTTP)
        router.get("/v1/portfolio-full/:userId").handler(this::handleFullPortfolio);

        // Error scenarios
        router.get("/v1/error/http").handler(this::handleErrorHttp);
        router.get("/v1/error/try-catch").handler(this::handleErrorTryCatch);

        // Global failure handler
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

        int port = Integer.parseInt(getEnvOrDefault("PORT", "8080"));

        // Schema init may fail or hang if DB is down — timeout + skip
        return repository.initializeSchema()
                .timeout(5, java.util.concurrent.TimeUnit.SECONDS)
                .onErrorComplete(err -> {
                    logger.warn("Schema init failed (DB may be down): {}", err.getMessage());
                    return true;
                })
                .andThen(vertx.createHttpServer()
                        .requestHandler(router)
                        .rxListen(port)
                        .doOnSuccess(server -> logger.info("HTTP server started on port {}", port))
                        .ignoreElement());
    }

    // ── Health ────────────────────────────────────────────────────

    private void handleHealth(RoutingContext ctx) {
        ctx.response()
                .putHeader("content-type", "application/json")
                .end(new JsonObject().put("status", "UP").encode());
    }

    // ── Holding CRUD (JDBC) ──────────────────────────────────────

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

    // ── Portfolio (WebClient) ────────────────────────────────────

    private void handleGetPortfolio(RoutingContext ctx) {
        String userId = ctx.pathParam("userId");
        logger.info("Fetching portfolio for user: {}", userId);

        holdingService.getHoldingsByUserId(userId)
                .flatMapObservable(holdings -> io.reactivex.Observable.fromIterable(holdings))
                .flatMapSingle(holding ->
                        webClient.getAbs(pricingServiceUrl + "/v1/price/" + holding.getSymbol())
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

    // ── External HTTP ────────────────────────────────────────────

    private void handleExternalJoke(RoutingContext ctx) {
        logger.info("Fetching from external API");
        webClient.getAbs("https://httpbin.org/get")
                .addQueryParam("source", "java8-agent-test")
                .rxSend()
                .subscribe(
                        response -> ctx.response()
                                .putHeader("content-type", "application/json")
                                .end(new JsonObject()
                                        .put("source", "httpbin.org")
                                        .put("status", response.statusCode())
                                        .encode()),
                        error -> handleError(ctx, error)
                );
    }

    private void handleExternalPost(RoutingContext ctx) {
        String postId = ctx.pathParam("id");
        logger.info("Fetching external post {}", postId);
        webClient.getAbs("https://jsonplaceholder.typicode.com/posts/" + postId)
                .rxSend()
                .subscribe(
                        response -> {
                            JsonObject post = response.bodyAsJsonObject();
                            ctx.response()
                                    .putHeader("content-type", "application/json")
                                    .end(new JsonObject()
                                            .put("source", "jsonplaceholder.typicode.com")
                                            .put("post", post)
                                            .encode());
                        },
                        error -> handleError(ctx, error)
                );
    }

    // ── Kafka ────────────────────────────────────────────────────

    private void handleKafkaProduce(RoutingContext ctx) {
        JsonObject body = ctx.getBodyAsJson();
        String key = body != null ? body.getString("key", "default") : "default";
        String value = body != null ? body.getString("value", "{}") : "{}";

        logger.info("Producing to Kafka topic '{}': key={}", kafkaTopic, key);

        KafkaProducerRecord<String, String> record =
                KafkaProducerRecord.create(kafkaTopic, key, value);

        kafkaProducer.rxSend(record)
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
                    KafkaProducerRecord<String, String> rec =
                            KafkaProducerRecord.create(kafkaTopic, prefix + "-" + i, event.encode());
                    return kafkaProducer.rxSend(rec);
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

    // ── Aerospike Cache ──────────────────────────────────────────

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

        vertx.<String>rxExecuteBlocking(promise -> {
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

    private void handleCacheGet(RoutingContext ctx) {
        String cacheKey = ctx.pathParam("key");

        if (aerospikeClient == null) {
            ctx.response().setStatusCode(503)
                    .end(new JsonObject().put("error", "Aerospike not available").encode());
            return;
        }

        vertx.<JsonObject>rxExecuteBlocking(promise -> {
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

    private void handleCacheDelete(RoutingContext ctx) {
        String cacheKey = ctx.pathParam("key");

        if (aerospikeClient == null) {
            ctx.response().setStatusCode(503)
                    .end(new JsonObject().put("error", "Aerospike not available").encode());
            return;
        }

        vertx.<Boolean>rxExecuteBlocking(promise -> {
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

    // ── MySQL Reactive ───────────────────────────────────────────

    private void handleMySQLPing(RoutingContext ctx) {
        if (mysqlPool == null) {
            ctx.response().setStatusCode(503)
                    .end(new JsonObject().put("error", "MySQL not available").encode());
            return;
        }

        mysqlPool.query("SELECT 1 AS alive, NOW() AS server_time")
                .rxExecute()
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

    // ── Full Portfolio (multi-system) ────────────────────────────

    private void handleFullPortfolio(RoutingContext ctx) {
        String userId = ctx.pathParam("userId");
        logger.info("Full portfolio for user: {} (DB + Cache + HTTP + Kafka)", userId);

        holdingService.getHoldingsByUserId(userId)
                .flatMapObservable(holdings -> io.reactivex.Observable.fromIterable(holdings))
                .flatMapSingle(holding -> {
                    String cacheKey = "price:" + holding.getSymbol();
                    return vertx.<JsonObject>rxExecuteBlocking(promise -> {
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
                                return webClient
                                        .getAbs(pricingServiceUrl + "/v1/price/" + holding.getSymbol())
                                        .rxSend()
                                        .map(response -> {
                                            JsonObject priceData = response.bodyAsJsonObject();
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

                    JsonObject event = new JsonObject()
                            .put("type", "portfolio_viewed")
                            .put("userId", userId)
                            .put("totalValue", total)
                            .put("holdingCount", portfolio.size())
                            .put("timestamp", System.currentTimeMillis());

                    KafkaProducerRecord<String, String> record =
                            KafkaProducerRecord.create(kafkaTopic, userId, event.encode());

                    double finalTotal = total;
                    return kafkaProducer.rxSend(record)
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

    // ── Error Scenarios ──────────────────────────────────────────

    private void handleErrorHttp(RoutingContext ctx) {
        String type = ctx.request().getParam("type");
        if (type == null) type = "runtime";
        try {
            if ("npe".equals(type)) {
                String s = null;
                s.length();
            } else if ("illegal".equals(type)) {
                throw new IllegalArgumentException("Simulated illegal argument: type=" + type);
            } else {
                throw new RuntimeException("Simulated runtime error for exception tracing demo");
            }
        } catch (Exception e) {
            logger.error("Simulated error (will appear as span exception event)", e);
            ctx.fail(e);
        }
    }

    private void handleErrorTryCatch(RoutingContext ctx) {
        Span span = Span.current();
        try {
            String divisor = ctx.request().getParam("divisor");
            if (divisor == null) divisor = "0";
            int result = 100 / Integer.parseInt(divisor);
            ctx.response()
                    .putHeader("content-type", "application/json")
                    .end(new JsonObject().put("result", result).encode());
        } catch (Exception e) {
            logger.error("Caught exception — recording on span manually", e);
            span.recordException(e);
            span.setStatus(StatusCode.ERROR, e.getMessage());
            ctx.response()
                    .setStatusCode(500)
                    .putHeader("content-type", "application/json")
                    .end(new JsonObject().put("error", e.getMessage()).encode());
        }
    }

    // ── Helpers ──────────────────────────────────────────────────

    private void handleError(RoutingContext ctx, Throwable error) {
        logger.error("Request failed", error);
        ctx.fail(500, error);
    }

    private String getEnvOrDefault(String name, String defaultValue) {
        String value = System.getenv(name);
        return value != null ? value : defaultValue;
    }
}
