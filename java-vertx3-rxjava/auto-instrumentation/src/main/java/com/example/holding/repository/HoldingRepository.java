package com.example.holding.repository;

import com.example.holding.model.Holding;
import io.reactivex.Completable;
import io.reactivex.Single;
import io.vertx.core.json.JsonArray;
import io.vertx.core.json.JsonObject;
import io.vertx.ext.jdbc.JDBCClient;
import io.vertx.ext.sql.ResultSet;
import io.vertx.ext.sql.SQLConnection;
import io.vertx.ext.sql.UpdateResult;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.stream.Collectors;

/**
 * Repository for Holding entity using Vert.x 3 JDBC client.
 * All database operations are automatically traced.
 */
public class HoldingRepository {

    private static final Logger logger = LoggerFactory.getLogger(HoldingRepository.class);

    private final JDBCClient jdbcClient;

    public HoldingRepository(JDBCClient jdbcClient) {
        this.jdbcClient = jdbcClient;
    }

    public Completable initializeSchema() {
        String createTableSql =
                "CREATE TABLE IF NOT EXISTS holdings (" +
                "id SERIAL PRIMARY KEY, " +
                "user_id VARCHAR(255) NOT NULL, " +
                "symbol VARCHAR(10) NOT NULL, " +
                "quantity INTEGER NOT NULL DEFAULT 0, " +
                "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, " +
                "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP" +
                ")";

        return getConnection()
                .flatMapCompletable(conn ->
                        execute(conn, createTableSql)
                                .doFinally(conn::close)
                                .doOnComplete(() -> logger.info("Database schema initialized"))
                );
    }

    public Single<List<Holding>> findAll() {
        String sql = "SELECT id, user_id, symbol, quantity FROM holdings ORDER BY id";
        return getConnection()
                .flatMap(conn ->
                        query(conn, sql)
                                .doFinally(conn::close)
                )
                .map(this::mapToHoldings);
    }

    public Single<List<Holding>> findByUserId(String userId) {
        String sql = "SELECT id, user_id, symbol, quantity FROM holdings WHERE user_id = ?";
        return getConnection()
                .flatMap(conn ->
                        queryWithParams(conn, sql, new JsonArray().add(userId))
                                .doFinally(conn::close)
                )
                .map(this::mapToHoldings);
    }

    public Single<Holding> save(Holding holding) {
        String sql = "INSERT INTO holdings (user_id, symbol, quantity) VALUES (?, ?, ?) RETURNING id, user_id, symbol, quantity";
        JsonArray params = new JsonArray()
                .add(holding.getUserId())
                .add(holding.getSymbol())
                .add(holding.getQuantity());

        return getConnection()
                .flatMap(conn ->
                        queryWithParams(conn, sql, params)
                                .doFinally(conn::close)
                )
                .map(rs -> {
                    if (rs.getRows().isEmpty()) {
                        throw new RuntimeException("Failed to insert holding");
                    }
                    return Holding.fromJson(rs.getRows().get(0));
                });
    }

    public Completable deleteById(Long id) {
        String sql = "DELETE FROM holdings WHERE id = ?";
        return getConnection()
                .flatMapCompletable(conn ->
                        updateWithParams(conn, sql, new JsonArray().add(id))
                                .doFinally(conn::close)
                                .flatMapCompletable(result -> {
                                    if (result.getUpdated() == 0) {
                                        return Completable.error(new RuntimeException("Holding not found"));
                                    }
                                    return Completable.complete();
                                })
                );
    }

    private Single<SQLConnection> getConnection() {
        return Single.create(emitter ->
                jdbcClient.getConnection(ar -> {
                    if (ar.succeeded()) {
                        emitter.onSuccess(ar.result());
                    } else {
                        emitter.onError(ar.cause());
                    }
                })
        );
    }

    private Completable execute(SQLConnection conn, String sql) {
        return Completable.create(emitter ->
                conn.execute(sql, ar -> {
                    if (ar.succeeded()) {
                        emitter.onComplete();
                    } else {
                        emitter.onError(ar.cause());
                    }
                })
        );
    }

    private Single<ResultSet> query(SQLConnection conn, String sql) {
        return Single.create(emitter ->
                conn.query(sql, ar -> {
                    if (ar.succeeded()) {
                        emitter.onSuccess(ar.result());
                    } else {
                        emitter.onError(ar.cause());
                    }
                })
        );
    }

    private Single<ResultSet> queryWithParams(SQLConnection conn, String sql, JsonArray params) {
        return Single.create(emitter ->
                conn.queryWithParams(sql, params, ar -> {
                    if (ar.succeeded()) {
                        emitter.onSuccess(ar.result());
                    } else {
                        emitter.onError(ar.cause());
                    }
                })
        );
    }

    private Single<UpdateResult> updateWithParams(SQLConnection conn, String sql, JsonArray params) {
        return Single.create(emitter ->
                conn.updateWithParams(sql, params, ar -> {
                    if (ar.succeeded()) {
                        emitter.onSuccess(ar.result());
                    } else {
                        emitter.onError(ar.cause());
                    }
                })
        );
    }

    private List<Holding> mapToHoldings(ResultSet rs) {
        return rs.getRows().stream()
                .map(Holding::fromJson)
                .collect(Collectors.toList());
    }
}
