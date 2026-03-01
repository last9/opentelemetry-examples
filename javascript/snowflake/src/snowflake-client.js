const snowflake = require('snowflake-sdk');
const { metrics, trace } = require('@opentelemetry/api');

// Get meter for custom metrics
const meter = metrics.getMeter('snowflake-client');

// Custom metrics
const queryCounter = meter.createCounter('snowflake.queries.total', {
  description: 'Total number of Snowflake queries executed'
});

const queryDuration = meter.createHistogram('snowflake.query.duration', {
  description: 'Duration of Snowflake queries in milliseconds',
  unit: 'ms'
});

const queryErrors = meter.createCounter('snowflake.queries.errors', {
  description: 'Total number of failed Snowflake queries'
});

const activeConnections = meter.createUpDownCounter('snowflake.connections.active', {
  description: 'Number of active Snowflake connections'
});

const rowsReturned = meter.createHistogram('snowflake.rows.returned', {
  description: 'Number of rows returned by queries'
});

// Snowflake connection configuration
const connectionConfig = {
  account: process.env.SNOWFLAKE_ACCOUNT,
  username: process.env.SNOWFLAKE_USER,
  password: process.env.SNOWFLAKE_PASSWORD,
  warehouse: process.env.SNOWFLAKE_WAREHOUSE,
  database: process.env.SNOWFLAKE_DATABASE,
  schema: process.env.SNOWFLAKE_SCHEMA,
  clientSessionKeepAlive: true,
  clientSessionKeepAliveHeartbeatFrequency: 3600,
  timeout: 60000, // 60 seconds
  authenticator: 'SNOWFLAKE'
};

const poolOptions = {
  max: parseInt(process.env.SNOWFLAKE_POOL_MAX || '5', 10),
  min: parseInt(process.env.SNOWFLAKE_POOL_MIN || '1', 10),
  usageTimeout: parseInt(process.env.SNOWFLAKE_POOL_TIMEOUT_MS || '30000', 10),
  retryLimit: parseInt(process.env.SNOWFLAKE_POOL_RETRY_LIMIT || '3', 10),
  retryDelay: parseInt(process.env.SNOWFLAKE_POOL_RETRY_DELAY_MS || '2000', 10),
  acquireTimeoutMillis: 30000,
  idleTimeoutMillis: 300000,
  evictionRunIntervalMillis: 30000,
  testOnBorrow: true
};

const QUERY_TIMEOUT_MS = parseInt(
  process.env.SNOWFLAKE_QUERY_TIMEOUT_MS || '20000',
  10
);

let snowflakePool;

// Create connection pool
const initializePool = () => {
  try {
    snowflakePool = snowflake.createPool(connectionConfig, poolOptions);
    console.log(
      `Snowflake connection pool created (min=${poolOptions.min}, max=${poolOptions.max})`
    );
  } catch (err) {
    console.error('Failed to create Snowflake connection pool:', err);
  }
};

// Initialize pool on module load
initializePool();

// Helper function to execute Snowflake query with telemetry
const executeQuery = (query, queryName = 'unknown') => {
  return new Promise((resolve, reject) => {
    const tracer = trace.getTracer('snowflake-client');
    const startTime = Date.now();

    tracer.startActiveSpan(`snowflake.query.${queryName}`, async (span) => {
      span.setAttribute('db.system', 'snowflake');
      span.setAttribute('db.name', connectionConfig.database);
      span.setAttribute('db.statement', query);
      span.setAttribute('query.name', queryName);

      if (!snowflakePool) {
        const error = new Error('Snowflake connection pool not initialized');
        queryErrors.add(1, { query: queryName, error: 'pool_unavailable' });
        span.recordException(error);
        span.setStatus({ code: 2, message: error.message });
        span.end();
        reject(error);
        return;
      }

      activeConnections.add(1, { query: queryName });

      try {
        const rows = await snowflakePool.use((clientConnection) => {
          return new Promise((res, rej) => {
            clientConnection.execute({
              sqlText: query,
              requestTimeout: QUERY_TIMEOUT_MS,
              complete: (err, stmt, resultRows) => {
                if (err) {
                  rej(err);
                  return;
                }
                res(resultRows);
              }
            });
          });
        });

        const duration = Date.now() - startTime;
        console.log(`Successfully executed ${queryName}. Rows:`, rows.length);

        queryCounter.add(1, { query: queryName, status: 'success' });
        queryDuration.record(duration, { query: queryName });
        rowsReturned.record(rows.length, { query: queryName });

        span.setAttribute('db.rows_returned', rows.length);
        span.setAttribute('db.query_duration_ms', duration);
        span.setStatus({ code: 1 });
        span.addEvent('Query completed', {
          rows: rows.length,
          duration_ms: duration
        });

        resolve(rows);
      } catch (err) {
        console.error(`Failed to execute ${queryName}:`, err);
        queryErrors.add(1, { query: queryName, error: err.code || 'execution_failed' });
        span.recordException(err);
        span.setStatus({ code: 2, message: err.message });
        reject(err);
      } finally {
        activeConnections.add(-1, { query: queryName });
        span.end();
      }
    });
  });
};

module.exports = {
  executeQuery,
  snowflakePool,
  initializePool
};
