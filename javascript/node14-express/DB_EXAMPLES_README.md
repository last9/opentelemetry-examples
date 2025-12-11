# Database and External Service Examples

This file (`db-examples.js`) contains comprehensive examples of OpenTelemetry instrumentation for various databases and external services with Node 14.

## Overview

The example demonstrates automatic instrumentation for:
- **PostgreSQL** - Connection pooling, parameterized queries, transactions
- **MySQL** - Connection pooling, JOINs, batch operations, transactions
- **MongoDB** - Find queries, aggregations, upserts
- **Redis** - Cache-aside pattern, rate limiting
- **HTTP Clients** - Multiple parallel API calls, retry logic with axios

## Prerequisites

### Install Database Clients

```bash
npm install pg mysql2 mongodb redis axios
```

### Database Setup

You need running instances of the databases. Use Docker for quick setup:

```bash
# PostgreSQL
docker run --name postgres -e POSTGRES_PASSWORD=password -p 5432:5432 -d postgres:14

# MySQL
docker run --name mysql -e MYSQL_ROOT_PASSWORD=password -p 3306:3306 -d mysql:8

# MongoDB
docker run --name mongo -p 27017:27017 -d mongo:5

# Redis
docker run --name redis -p 6379:6379 -d redis:7-alpine
```

### Database Schema

Create the required tables/collections:

#### PostgreSQL

```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100),
  email VARCHAR(100) UNIQUE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE audit_log (
  id SERIAL PRIMARY KEY,
  action VARCHAR(50),
  user_id INTEGER,
  timestamp TIMESTAMP DEFAULT NOW()
);
```

#### MySQL

```sql
CREATE TABLE products (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100),
  price DECIMAL(10, 2),
  stock INT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT,
  total DECIMAL(10, 2),
  status VARCHAR(20),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE order_items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  order_id INT,
  product_id INT,
  quantity INT,
  FOREIGN KEY (order_id) REFERENCES orders(id),
  FOREIGN KEY (product_id) REFERENCES products(id)
);
```

#### MongoDB

```javascript
// Collections: products, orders, carts, order_details
// No schema required - MongoDB is schemaless
```

## Running the Examples

### 1. Configure Environment Variables

```bash
# PostgreSQL
export PG_HOST=localhost
export PG_PORT=5432
export PG_DATABASE=testdb
export PG_USER=postgres
export PG_PASSWORD=password

# MySQL
export MYSQL_HOST=localhost
export MYSQL_PORT=3306
export MYSQL_DATABASE=testdb
export MYSQL_USER=root
export MYSQL_PASSWORD=password

# MongoDB
export MONGO_URI=mongodb://localhost:27017
export MONGO_DB=testdb

# Redis
export REDIS_HOST=localhost
export REDIS_PORT=6379

# Last9 Configuration
export OTEL_SERVICE_NAME=node14-db-examples
export OTEL_EXPORTER_OTLP_ENDPOINT=https://<your-last9-endpoint>
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic YOUR_TOKEN_HERE"
```

### 2. Start the Server

```bash
npm run start:db-examples
# Or directly:
node -r ./instrumentation.js db-examples.js
```

## API Endpoints

### PostgreSQL Examples

#### 1. Get All Users
```bash
GET /api/pg/users
```

Demonstrates:
- Connection pooling
- Simple SELECT query
- Custom span attributes
- Error handling

#### 2. Create User (with Transaction)
```bash
POST /api/pg/users
Content-Type: application/json

{
  "name": "John Doe",
  "email": "john@example.com"
}
```

Demonstrates:
- Parameterized queries (SQL injection prevention)
- Database transactions (BEGIN/COMMIT/ROLLBACK)
- Multiple queries in a transaction
- Audit logging

### MySQL Examples

#### 3. Get User Orders (with JOIN)
```bash
GET /api/mysql/orders/1
```

Demonstrates:
- Connection pooling
- Complex JOIN queries
- Parameterized queries
- Query result processing

#### 4. Bulk Insert Products
```bash
POST /api/mysql/products/bulk
Content-Type: application/json

{
  "products": [
    {"name": "Product 1", "price": 19.99, "stock": 100},
    {"name": "Product 2", "price": 29.99, "stock": 50}
  ]
}
```

Demonstrates:
- Batch INSERT operations
- Transaction handling
- Efficient bulk operations

### MongoDB Examples

#### 5. Find Products (with Filtering)
```bash
GET /api/mongo/products?category=electronics&minPrice=100&maxPrice=500
```

Demonstrates:
- Find with complex filters
- Query projection
- Limit and pagination
- Dynamic filter building

#### 6. Sales Report (Aggregation)
```bash
GET /api/mongo/sales-report
```

Demonstrates:
- Aggregation pipeline
- $match, $group, $sort stages
- Date calculations
- Complex data transformations

#### 7. Update Shopping Cart (Upsert)
```bash
PUT /api/mongo/cart/123
Content-Type: application/json

{
  "items": [
    {"productId": "p1", "quantity": 2},
    {"productId": "p2", "quantity": 1}
  ]
}
```

Demonstrates:
- Upsert operations (update or insert)
- $set and $setOnInsert operators
- Handling create vs update logic

### Redis Examples

#### 8. Cache-Aside Pattern
```bash
GET /api/cache/user/123
```

Demonstrates:
- Cache-aside pattern
- Redis GET operations
- Cache miss handling
- Database fallback
- SETEX (set with expiration)
- Cache hit/miss tracking

#### 9. Rate Limiting
```bash
GET /api/rate-limited/resource
```

Demonstrates:
- Token bucket rate limiting
- Redis INCR for atomic counters
- TTL (time-to-live) management
- Rate limit headers
- 429 Too Many Requests response

### External API Examples

#### 10. Multi-Service Dashboard
```bash
GET /api/external/user-dashboard/1
```

Demonstrates:
- Multiple parallel HTTP requests
- Promise.all for concurrent operations
- External API integration
- Data aggregation
- axios with OpenTelemetry auto-instrumentation

#### 11. Notification with Retry Logic
```bash
POST /api/external/notify
Content-Type: application/json

{
  "recipient": "user@example.com",
  "message": "Your order is ready!"
}
```

Demonstrates:
- HTTP POST requests
- Retry logic with exponential backoff
- Timeout handling
- Request headers
- Error recovery strategies

### Complex Workflow

#### 12. Complete Order Processing
```bash
POST /api/orders/process
Content-Type: application/json

{
  "userId": 1,
  "items": [
    {"productId": 1, "quantity": 2, "price": 19.99},
    {"productId": 2, "quantity": 1, "price": 29.99}
  ]
}
```

Demonstrates:
- Multi-database transaction
- PostgreSQL + MySQL + MongoDB + Redis coordination
- External API call within transaction
- Complex error handling
- Distributed transaction pattern
- Rollback on failure

## OpenTelemetry Features Demonstrated

### Auto-Instrumentation
All database clients are automatically instrumented by OpenTelemetry without any code changes:
- **PostgreSQL** (`pg` package)
- **MySQL** (`mysql2` package)
- **MongoDB** (`mongodb` package)
- **Redis** (`redis` package)
- **HTTP** (`axios`, `http`, `https`)

### Trace Context Propagation
- Automatic parent-child span relationships
- Distributed tracing across services
- Trace ID included in all responses

### Span Attributes
Each database operation includes rich metadata:
- `db.system` - Database type (postgresql, mysql, mongodb, redis)
- `db.statement` - SQL query or operation
- `db.operation` - Type of operation (SELECT, INSERT, etc.)
- `db.rows_returned` - Number of results
- Custom business attributes

### Error Tracking
- Exceptions recorded in spans
- Span status set to ERROR
- Stack traces captured
- Error propagation

## Best Practices Demonstrated

### 1. Connection Pooling
- Reuse database connections
- Configure pool limits
- Handle connection errors

### 2. SQL Injection Prevention
- Always use parameterized queries
- Never concatenate user input into SQL
- Use prepared statements

### 3. Transaction Management
- Explicit BEGIN/COMMIT/ROLLBACK
- Error handling with rollback
- Nested transaction considerations

### 4. Cache Strategies
- Cache-aside (lazy loading)
- TTL (time-to-live) management
- Cache invalidation
- Fallback to database

### 5. Rate Limiting
- Token bucket algorithm
- Redis for atomic counters
- Proper HTTP status codes (429)
- Retry-After headers

### 6. Retry Logic
- Exponential backoff
- Maximum retry attempts
- Timeout handling
- Idempotency considerations

### 7. Resource Cleanup
- Graceful shutdown
- Connection release
- Transaction cleanup
- Process signal handling

## Viewing Traces in Last9

After running the examples, view traces in Last9:

1. Navigate to Last9 dashboard
2. Go to Traces section
3. Filter by service: `node14-db-examples`
4. Look for spans with these operations:
   - `pg.query` - PostgreSQL operations
   - `mysql.query` - MySQL operations
   - `mongodb.find` / `mongodb.aggregate` - MongoDB operations
   - `redis.get` / `redis.set` - Redis operations
   - `HTTP GET` / `HTTP POST` - External API calls

## Metrics in Last9

The instrumentation also exports metrics:

**Runtime Metrics:**
- `nodejs.memory.heap.used` - Heap memory usage
- `nodejs.memory.rss` - Resident set size
- `nodejs.eventloop.lag` - Event loop lag
- `nodejs.active_handles` - Active handles count

**Database Metrics:**
- Connection pool usage
- Query duration
- Query count
- Error rates

## Troubleshooting

### Database Connection Errors

```bash
# PostgreSQL
psql -h localhost -U postgres -d testdb

# MySQL
mysql -h localhost -u root -p testdb

# MongoDB
mongosh mongodb://localhost:27017/testdb

# Redis
redis-cli ping
```

### No Traces Appearing

1. Check Last9 credentials
2. Verify OTEL_EXPORTER_OTLP_ENDPOINT
3. Check logs for export errors
4. Enable debug logging in instrumentation.js

### Performance Considerations

- Connection pool sizes affect performance
- Batch operations are more efficient
- Index your database queries
- Monitor event loop lag
- Use caching appropriately

## Additional Resources

- [OpenTelemetry JavaScript Documentation](https://opentelemetry.io/docs/languages/js/)
- [PostgreSQL Node.js Driver](https://node-postgres.com/)
- [MySQL2 Documentation](https://github.com/sidorares/node-mysql2)
- [MongoDB Node.js Driver](https://www.mongodb.com/docs/drivers/node/current/)
- [Redis Node.js Client](https://github.com/redis/node-redis)
- [Axios Documentation](https://axios-http.com/)
- [Last9 Documentation](https://docs.last9.io)

## License

This example is provided for educational purposes.
