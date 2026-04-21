package com.example.holding.repository;

import com.example.holding.model.Holding;
import io.reactivex.Completable;
import io.reactivex.Single;
import io.vertx.core.json.JsonArray;
import io.vertx.ext.sql.ResultSet;
import io.vertx.reactivex.ext.sql.SQLClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.stream.Collectors;

/**
 * Repository for Holding entity using Vert.x 3 rx SQLClient.
 * All queries get automatic OTel CLIENT spans via JdbcClientAdvice auto-instrumentation.
 */
public class HoldingRepository {

    private static final Logger logger = LoggerFactory.getLogger(HoldingRepository.class);

    private final SQLClient sqlClient;

    public HoldingRepository(SQLClient sqlClient) {
        this.sqlClient = sqlClient;
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

        return sqlClient.rxGetConnection()
                .flatMapCompletable(conn ->
                        conn.rxExecute(createTableSql)
                                .doFinally(conn::close)
                                .doOnComplete(() -> logger.info("Database schema initialized"))
                );
    }

    public Single<List<Holding>> findAll() {
        String sql = "SELECT id, user_id, symbol, quantity FROM holdings ORDER BY id";
        return sqlClient.rxQuery(sql)
                .map(this::mapToHoldings);
    }

    public Single<List<Holding>> findByUserId(String userId) {
        String sql = "SELECT id, user_id, symbol, quantity FROM holdings WHERE user_id = ?";
        return sqlClient.rxQueryWithParams(sql, new JsonArray().add(userId))
                .map(this::mapToHoldings);
    }

    public Single<Holding> save(Holding holding) {
        String sql = "INSERT INTO holdings (user_id, symbol, quantity) VALUES (?, ?, ?) RETURNING id, user_id, symbol, quantity";
        JsonArray params = new JsonArray()
                .add(holding.getUserId())
                .add(holding.getSymbol())
                .add(holding.getQuantity());

        return sqlClient.rxQueryWithParams(sql, params)
                .map(rs -> {
                    if (rs.getRows().isEmpty()) {
                        throw new RuntimeException("Failed to insert holding");
                    }
                    return Holding.fromJson(rs.getRows().get(0));
                });
    }

    public Completable deleteById(Long id) {
        String sql = "DELETE FROM holdings WHERE id = ?";
        return sqlClient.rxUpdateWithParams(sql, new JsonArray().add(id))
                .flatMapCompletable(result -> {
                    if (result.getUpdated() == 0) {
                        return Completable.error(new RuntimeException("Holding not found"));
                    }
                    return Completable.complete();
                });
    }

    private List<Holding> mapToHoldings(ResultSet rs) {
        return rs.getRows().stream()
                .map(Holding::fromJson)
                .collect(Collectors.toList());
    }
}
