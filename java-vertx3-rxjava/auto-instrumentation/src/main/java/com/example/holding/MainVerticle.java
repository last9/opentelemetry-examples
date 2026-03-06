package com.example.holding;

import com.aerospike.client.AerospikeClient;
import com.aerospike.client.Bin;
import com.aerospike.client.Key;
import com.aerospike.client.Record;
import com.aerospike.client.policy.ClientPolicy;
import com.example.holding.model.Holding;
import com.example.holding.repository.HoldingRepository;
import com.example.holding.service.HoldingService;
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
 * Demonstrates Vert.x 3 with RxJava2 and ZERO-CODE OpenTelemetry auto-instrumentation.
 *
 * No Traced* wrappers are used — all tracing is handled automatically by the
 * ByteBuddy agent installed by OtelLauncher:
 * - Router:         SERVER spans via RouterImplAdvice
 * - WebClient:      CLIENT spans + traceparent via WebClientAdvice
 * - JDBCClient:     CLIENT spans via JdbcClientAdvice
 * - KafkaProducer:  PRODUCER spans via KafkaProducerAdvice
 * - KafkaConsumer:  CONSUMER spans via KafkaConsumerAdvice
 * - AerospikeClient: CLIENT spans via AerospikeClientAdvice
 * - MySQLPool:      CLIENT spans via ReactiveSqlAdvice
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
        logger.info("Starting MainVerticle (zero-code tracing mode)...");

        // Plain JDBC client — auto-instrumented by JdbcClientAdvice
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

        // Plain WebClient — auto-instrumented by WebClientAdvice
        webClient = WebClient.create(vertx);

        pricingServiceUrl = getEnvOrDefault("PRICING_SERVICE_URL", "http://localhost:8081");

        // Plain Kafka producer — auto-instrumented by KafkaProducerAdvice
        kafkaTopic = getEnvOrDefault("KAFKA_TOPIC", "holding-events");
        Map<String, String> kafkaConfig = new HashMap<>();
        kafkaConfig.put("bootstrap.servers", getEnvOrDefault("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"));
        kafkaConfig.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        kafkaConfig.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        kafkaConfig.put("acks", "1");
        kafkaProducer = KafkaProducer.create(vertx, kafkaConfig);

        // Plain Kafka consumer — auto-instrumented by KafkaConsumerAdvice
        Map<String, String> consumerConfig = new HashMap<>();
        consumerConfig.put("bootstrap.servers", getEnvOrDefault("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"));
        consumerConfig.put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
        consumerConfig.put("value.deserializer", "org.apache.kafka.common.serialization.StringDeserializer");
        consumerConfig.put("group.id", "holding-service-consumer");
        consumerConfig.put("auto.offset.reset", "earliest");
        consumerConfig.put("enable.auto.commit", "true");

        KafkaConsumer<String, String> consumer = KafkaConsumer.create(vertx, consumerConfig);
        consumer.handler(record -> {
            logger.info("Consumed record: key={}, value={}", record.key(), record.value());

            if (record.value() != null && record.value().startsWith("__poison__")) {
                throw new RuntimeException("Poison-pill message detected: key=" + record.key()
                        + ", value=" + record.value());
            }

            // Process: cache in Aerospike + outbound HTTP enrichment
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

            webClient.getAbs(pricingServiceUrl + "/v1/price/AAPL")
                    .rxSend()
                    .subscribe(
                            resp -> logger.info("Consumer enrichment: status={}", resp.statusCode()),
                            err -> logger.debug("Enrichment failed: {}", err.getMessage()));
        });
        consumer.subscribe(kafkaTopic);

        // Plain Aerospike client — auto-instrumented by AerospikeClientAdvice
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

        // Plain MySQL reactive pool — auto-instrumented by ReactiveSqlAdvice
        try {
            MySQLConnectOptions mysqlOptions = new MySQLConnectOptions()
                    .setHost(getEnvOrDefault("MYSQL_HOST", "localhost"))
                    .setPort(Integer.parseInt(getEnvOrDefault("MYSQL_PORT", "3306")))
                    .setDatabase(getEnvOrDefault("MYSQL_DB", "testdb"))
                    .setUser(getEnvOrDefault("MYSQL_USER", "root"))
                    .setPassword(getEnvOrDefault("MYSQL_PASSWORD", "root"));
            PoolOptions poolOptions = new PoolOptions().setMaxSize(5);
            mysqlPool = MySQLPool.pool(vertx, mysqlOptions, poolOptions);
            logger.info("MySQL pool created ({}:{})", getEnvOrDefault("MYSQL_HOST", "localhost"),
                    getEnvOrDefault("MYSQL_PORT", "3306"));
        } catch (Exception e) {
            logger.warn("MySQL not available — /v1/mysql/* endpoints will return errors: {}", e.getMessage());
        }

        // Plain Router — auto-instrumented by RouterImplAdvice
        Router router = Router.router(vertx);

        // Health check endpoint
        router.get("/health").handler(this::handleHealth);

        // Holding endpoints (SQL auto-traced by JdbcClientAdvice)
        router.get("/v1/holding").handler(this::handleGetAllHoldings);
        router.get("/v1/holding/:userId").handler(this::handleGetHoldingsByUser);
        router.post("/v1/holding").handler(this::handleCreateHolding);
        router.delete("/v1/holding/:id").handler(this::handleDeleteHolding);

        // Portfolio — outbound HTTP auto-traced by WebClientAdvice
        router.get("/v1/portfolio/:userId").handler(this::handleGetPortfolio);

        // External public API calls
        router.get("/v1/external/joke").handler(this::handleExternalJoke);
        router.get("/v1/external/post/:id").handler(this::handleExternalPost);

        // Kafka endpoints — auto-traced by KafkaProducerAdvice
        router.post("/v1/kafka/produce").handler(this::handleKafkaProduce);
        router.post("/v1/kafka/produce-batch").handler(this::handleKafkaProduceBatch);
        router.delete("/v1/kafka/tombstone/:key").handler(this::handleKafkaTombstone);

        // Aerospike endpoints — auto-traced by AerospikeClientAdvice
        router.post("/v1/cache/:key").handler(this::handleCachePut);
        router.get("/v1/cache/:key").handler(this::handleCacheGet);
        router.delete("/v1/cache/:key").handler(this::handleCacheDelete);

        // MySQL reactive client endpoints — auto-traced by ReactiveSqlAdvice
        router.get("/v1/mysql/ping").handler(this::handleMySQLPing);
        router.get("/v1/mysql/query").handler(this::handleMySQLQuery);

        // Complex multi-system endpoint — DB + Aerospike + Kafka + outbound HTTP
        router.get("/v1/portfolio-full/:userId").handler(this::handleFullPortfolio);

        // Exception scenario endpoints
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

        int port = Integer.parseInt(getEnvOrDefault("APP_PORT", "8080"));

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
     * Portfolio endpoint — outbound HTTP calls auto-traced by WebClientAdvice.
     */
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

    /**
     * External API call — auto-traced by WebClientAdvice.
     */
    private void handleExternalJoke(RoutingContext ctx) {
        logger.info("Fetching from external API");

        webClient.getAbs("https://httpbin.org/get")
                .addQueryParam("source", "holding-service")
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

    /**
     * External API call — auto-traced by WebClientAdvice.
     */
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

    // ---- Kafka Handlers ----

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
                    KafkaProducerRecord<String, String> record =
                            KafkaProducerRecord.create(kafkaTopic, prefix + "-" + i, event.encode());
                    return kafkaProducer.rxSend(record);
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

    private void handleKafkaTombstone(RoutingContext ctx) {
        String key = ctx.pathParam("key");
        logger.info("Sending Kafka tombstone for key '{}' on topic '{}'", key, kafkaTopic);

        KafkaProducerRecord<String, String> record =
                KafkaProducerRecord.create(kafkaTopic, key, null);

        kafkaProducer.rxSend(record)
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

    // ---- MySQL Handlers ----

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

    private void handleMySQLQuery(RoutingContext ctx) {
        if (mysqlPool == null) {
            ctx.response().setStatusCode(503)
                    .end(new JsonObject().put("error", "MySQL not available").encode());
            return;
        }

        String sql = ctx.request().getParam("sql");
        if (sql == null || sql.isBlank()) {
            sql = "SHOW TABLES";
        }
        String finalSql = sql;

        mysqlPool.query(finalSql)
                .rxExecute()
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

    private void handleError(RoutingContext ctx, Throwable error) {
        logger.error("Request failed", error);
        ctx.fail(500, error);
    }

    private String getEnvOrDefault(String name, String defaultValue) {
        String value = System.getenv(name);
        return value != null ? value : defaultValue;
    }
}
