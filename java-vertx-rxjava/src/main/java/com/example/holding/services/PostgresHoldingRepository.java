package com.example.holding.services;

import com.example.holding.dto.HoldingData;
import io.otel.rxjava.vertx.operators.Traced;
import io.reactivex.rxjava3.core.Single;
import io.vertx.pgclient.PgConnectOptions;
import io.vertx.rxjava3.pgclient.PgPool;
import io.vertx.rxjava3.sqlclient.Row;
import io.vertx.rxjava3.sqlclient.RowSet;
import io.vertx.rxjava3.sqlclient.Tuple;
import io.vertx.sqlclient.PoolOptions;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * PostgreSQL repository for holdings data.
 * Demonstrates traced database operations.
 */
public class PostgresHoldingRepository {
    private static final Logger log = LoggerFactory.getLogger(PostgresHoldingRepository.class);

    private final PgPool pgPool;
    private boolean initialized = false;

    public PostgresHoldingRepository(io.vertx.rxjava3.core.Vertx vertx) {
        String host = System.getenv().getOrDefault("POSTGRES_HOST", "localhost");
        int port = Integer.parseInt(System.getenv().getOrDefault("POSTGRES_PORT", "5432"));
        String database = System.getenv().getOrDefault("POSTGRES_DB", "holdingdb");
        String user = System.getenv().getOrDefault("POSTGRES_USER", "postgres");
        String password = System.getenv().getOrDefault("POSTGRES_PASSWORD", "postgres");

        PgConnectOptions connectOptions = new PgConnectOptions()
                .setPort(port)
                .setHost(host)
                .setDatabase(database)
                .setUser(user)
                .setPassword(password);

        PoolOptions poolOptions = new PoolOptions()
                .setMaxSize(5);

        this.pgPool = PgPool.pool(vertx, connectOptions, poolOptions);
        log.info("PostgreSQL connection pool created for {}:{}/{}", host, port, database);
    }

    /**
     * Initialize the database schema and seed data
     */
    public Single<Boolean> initialize() {
        if (initialized) {
            return Single.just(true);
        }

        return Traced.single("PostgresRepository.initialize", () ->
                pgPool.query("""
                    CREATE TABLE IF NOT EXISTS holdings (
                        id SERIAL PRIMARY KEY,
                        user_id VARCHAR(50) NOT NULL,
                        symbol VARCHAR(20) NOT NULL,
                        trading_type VARCHAR(20) NOT NULL,
                        quantity INTEGER NOT NULL,
                        avg_price DECIMAL(12,2) NOT NULL,
                        current_price DECIMAL(12,2) NOT NULL,
                        pnl DECIMAL(12,2) NOT NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                    """).rxExecute()
                        .flatMap(rs -> {
                            log.info("Holdings table created/verified");
                            return seedDataIfEmpty();
                        })
                        .map(rs -> {
                            initialized = true;
                            return true;
                        })
        );
    }

    private Single<RowSet<Row>> seedDataIfEmpty() {
        return pgPool.query("SELECT COUNT(*) as cnt FROM holdings").rxExecute()
                .flatMap(rs -> {
                    Row row = rs.iterator().next();
                    long count = row.getLong("cnt");
                    if (count == 0) {
                        log.info("Seeding holdings table with sample data");
                        return seedData();
                    }
                    log.info("Holdings table already has {} records", count);
                    return Single.just(rs);
                });
    }

    private Single<RowSet<Row>> seedData() {
        String insertSql = """
            INSERT INTO holdings (user_id, symbol, trading_type, quantity, avg_price, current_price, pnl)
            VALUES
                ('user123', 'RELIANCE', 'EQUITY', 100, 2450.50, 2520.75, 7025.00),
                ('user123', 'TCS', 'EQUITY', 50, 3800.00, 3750.25, -2487.50),
                ('user123', 'NIFTY24FEB', 'F&O', 25, 21500.00, 21750.00, 6250.00),
                ('user456', 'INFY', 'EQUITY', 200, 1450.00, 1480.50, 6100.00),
                ('user456', 'HDFC', 'EQUITY', 75, 1650.00, 1620.00, -2250.00),
                ('testuser123', 'RELIANCE', 'EQUITY', 150, 2400.00, 2520.75, 18112.50),
                ('testuser123', 'WIPRO', 'EQUITY', 100, 420.00, 435.50, 1550.00)
            """;
        return pgPool.query(insertSql).rxExecute();
    }

    /**
     * Fetch holdings from PostgreSQL by user ID
     */
    public Single<List<HoldingData>> fetchHoldingsByUserId(String userId) {
        return Traced.single(
                "PostgresRepository.fetchHoldingsByUserId",
                Map.of("user.id", userId, "db.system", "postgresql"),
                () -> pgPool.preparedQuery(
                        "SELECT symbol, trading_type, quantity, avg_price, current_price, pnl FROM holdings WHERE user_id = $1"
                        )
                        .rxExecute(Tuple.of(userId))
                        .map(rows -> {
                            List<HoldingData> holdings = new ArrayList<>();
                            for (Row row : rows) {
                                holdings.add(new HoldingData(
                                        row.getString("symbol"),
                                        row.getString("trading_type"),
                                        row.getInteger("quantity"),
                                        row.getDouble("avg_price"),
                                        row.getDouble("current_price"),
                                        row.getDouble("pnl")
                                ));
                            }
                            log.info("Fetched {} holdings from PostgreSQL for user {}", holdings.size(), userId);
                            return holdings;
                        })
        );
    }

    /**
     * Fetch holdings by user ID and trading types
     */
    public Single<List<HoldingData>> fetchHoldingsByUserIdAndTradingTypes(
            String userId, List<String> tradingTypes) {

        return Traced.single(
                "PostgresRepository.fetchByUserAndTypes",
                Map.of(
                        "user.id", userId,
                        "trading.types", tradingTypes.toString(),
                        "db.system", "postgresql"
                ),
                () -> {
                    // Build dynamic query for trading types
                    StringBuilder placeholders = new StringBuilder();
                    Tuple params = Tuple.of(userId);
                    for (int i = 0; i < tradingTypes.size(); i++) {
                        if (i > 0) placeholders.append(", ");
                        placeholders.append("$").append(i + 2);
                        params = params.addString(tradingTypes.get(i));
                    }

                    String sql = String.format(
                            "SELECT symbol, trading_type, quantity, avg_price, current_price, pnl " +
                                    "FROM holdings WHERE user_id = $1 AND trading_type IN (%s)",
                            placeholders
                    );

                    final Tuple finalParams = params;
                    return pgPool.preparedQuery(sql)
                            .rxExecute(finalParams)
                            .map(rows -> {
                                List<HoldingData> holdings = new ArrayList<>();
                                for (Row row : rows) {
                                    holdings.add(new HoldingData(
                                            row.getString("symbol"),
                                            row.getString("trading_type"),
                                            row.getInteger("quantity"),
                                            row.getDouble("avg_price"),
                                            row.getDouble("current_price"),
                                            row.getDouble("pnl")
                                    ));
                                }
                                log.info("Fetched {} holdings from PostgreSQL for user {} with types {}",
                                        holdings.size(), userId, tradingTypes);
                                return holdings;
                            });
                }
        );
    }

    /**
     * Insert a new holding
     */
    public Single<Boolean> insertHolding(String userId, HoldingData holding) {
        return Traced.single(
                "PostgresRepository.insertHolding",
                Map.of(
                        "user.id", userId,
                        "symbol", holding.getSymbol(),
                        "db.system", "postgresql",
                        "db.operation", "INSERT"
                ),
                () -> pgPool.preparedQuery(
                                "INSERT INTO holdings (user_id, symbol, trading_type, quantity, avg_price, current_price, pnl) " +
                                        "VALUES ($1, $2, $3, $4, $5, $6, $7)"
                        )
                        .rxExecute(Tuple.tuple()
                                .addString(userId)
                                .addString(holding.getSymbol())
                                .addString(holding.getTradingType())
                                .addInteger(holding.getQuantity())
                                .addDouble(holding.getAvgPrice())
                                .addDouble(holding.getCurrentPrice())
                                .addDouble(holding.getPnl())
                        )
                        .map(rs -> {
                            log.info("Inserted holding {} for user {}", holding.getSymbol(), userId);
                            return true;
                        })
        );
    }

    /**
     * Get total holdings count
     */
    public Single<Long> getTotalHoldingsCount() {
        return Traced.single(
                "PostgresRepository.getTotalCount",
                Map.of("db.system", "postgresql", "db.operation", "SELECT COUNT"),
                () -> pgPool.query("SELECT COUNT(*) as total FROM holdings")
                        .rxExecute()
                        .map(rows -> {
                            long count = rows.iterator().next().getLong("total");
                            log.info("Total holdings in database: {}", count);
                            return count;
                        })
        );
    }

    /**
     * Close the pool
     */
    public void close() {
        pgPool.close();
    }
}
