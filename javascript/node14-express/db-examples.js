const express = require('express');
const opentelemetry = require('@opentelemetry/api');

// Database client imports (install separately)
// npm install pg mysql2 mongodb redis axios

const { Pool } = require('pg');
const mysql = require('mysql2/promise');
const { MongoClient } = require('mongodb');
const redis = require('redis');
const axios = require('axios');

const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());

// Helper function to get current trace ID
function getTraceId() {
  const span = opentelemetry.trace.getActiveSpan();
  if (span) {
    return span.spanContext().traceId;
  }
  return null;
}

// ============================================
// POSTGRESQL EXAMPLES
// ============================================

// PostgreSQL connection pool
const pgPool = new Pool({
  host: process.env.PG_HOST || 'localhost',
  port: process.env.PG_PORT || 5432,
  database: process.env.PG_DATABASE || 'testdb',
  user: process.env.PG_USER || 'postgres',
  password: process.env.PG_PASSWORD || 'password',
  max: 10,
  idleTimeoutMillis: 30000,
});

// 1. PostgreSQL - Simple SELECT query
app.get('/api/pg/users', async (req, res) => {
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const span = tracer.startSpan('pg.get_all_users');

  try {
    const result = await pgPool.query('SELECT id, name, email FROM users LIMIT 10');

    span.setAttribute('db.rows_returned', result.rows.length);
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

    res.json({
      users: result.rows,
      count: result.rows.length,
      traceId: getTraceId(),
    });
  } catch (error) {
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
    res.status(500).json({ error: error.message, traceId: getTraceId() });
  } finally {
    span.end();
  }
});

// 2. PostgreSQL - Parameterized query with transaction
app.post('/api/pg/users', async (req, res) => {
  const { name, email } = req.body;
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const span = tracer.startSpan('pg.create_user');

  const client = await pgPool.connect();

  try {
    await client.query('BEGIN');

    const insertQuery = 'INSERT INTO users(name, email, created_at) VALUES($1, $2, NOW()) RETURNING id, name, email';
    const result = await client.query(insertQuery, [name, email]);

    // Simulate audit log insert
    await client.query('INSERT INTO audit_log(action, user_id, timestamp) VALUES($1, $2, NOW())',
      ['user_created', result.rows[0].id]);

    await client.query('COMMIT');

    span.setAttribute('user.id', result.rows[0].id);
    span.setAttribute('user.email', email);
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

    res.status(201).json({
      user: result.rows[0],
      traceId: getTraceId(),
    });
  } catch (error) {
    await client.query('ROLLBACK');
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
    res.status(500).json({ error: error.message, traceId: getTraceId() });
  } finally {
    client.release();
    span.end();
  }
});

// ============================================
// MYSQL EXAMPLES
// ============================================

// MySQL connection pool
const mysqlPool = mysql.createPool({
  host: process.env.MYSQL_HOST || 'localhost',
  port: process.env.MYSQL_PORT || 3306,
  database: process.env.MYSQL_DATABASE || 'testdb',
  user: process.env.MYSQL_USER || 'root',
  password: process.env.MYSQL_PASSWORD || 'password',
  waitForConnections: true,
  connectionLimit: 10,
});

// 3. MySQL - SELECT with JOIN
app.get('/api/mysql/orders/:userId', async (req, res) => {
  const { userId } = req.params;
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const span = tracer.startSpan('mysql.get_user_orders');
  span.setAttribute('user.id', userId);

  try {
    const [rows] = await mysqlPool.execute(
      `SELECT o.id, o.total, o.status, o.created_at, p.name as product_name
       FROM orders o
       JOIN order_items oi ON o.id = oi.order_id
       JOIN products p ON oi.product_id = p.id
       WHERE o.user_id = ?
       ORDER BY o.created_at DESC
       LIMIT 20`,
      [userId]
    );

    span.setAttribute('db.rows_returned', rows.length);
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

    res.json({
      orders: rows,
      count: rows.length,
      traceId: getTraceId(),
    });
  } catch (error) {
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
    res.status(500).json({ error: error.message, traceId: getTraceId() });
  } finally {
    span.end();
  }
});

// 4. MySQL - Batch INSERT
app.post('/api/mysql/products/bulk', async (req, res) => {
  const { products } = req.body; // Array of {name, price, stock}
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const span = tracer.startSpan('mysql.bulk_insert_products');
  span.setAttribute('products.count', products.length);

  const connection = await mysqlPool.getConnection();

  try {
    await connection.beginTransaction();

    const insertQuery = 'INSERT INTO products (name, price, stock, created_at) VALUES ?';
    const values = products.map(p => [p.name, p.price, p.stock, new Date()]);

    const [result] = await connection.query(insertQuery, [values]);

    await connection.commit();

    span.setAttribute('db.rows_inserted', result.affectedRows);
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

    res.status(201).json({
      inserted: result.affectedRows,
      traceId: getTraceId(),
    });
  } catch (error) {
    await connection.rollback();
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
    res.status(500).json({ error: error.message, traceId: getTraceId() });
  } finally {
    connection.release();
    span.end();
  }
});

// ============================================
// MONGODB EXAMPLES
// ============================================

// MongoDB client
let mongoClient;
let mongoDb;

async function connectMongo() {
  if (!mongoClient) {
    const uri = process.env.MONGO_URI || 'mongodb://localhost:27017';
    mongoClient = new MongoClient(uri);
    await mongoClient.connect();
    mongoDb = mongoClient.db(process.env.MONGO_DB || 'testdb');
  }
  return mongoDb;
}

// 5. MongoDB - Find with filter and projection
app.get('/api/mongo/products', async (req, res) => {
  const { category, minPrice, maxPrice } = req.query;
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const span = tracer.startSpan('mongo.find_products');

  try {
    const db = await connectMongo();
    const collection = db.collection('products');

    const filter = {};
    if (category) filter.category = category;
    if (minPrice || maxPrice) {
      filter.price = {};
      if (minPrice) filter.price.$gte = parseFloat(minPrice);
      if (maxPrice) filter.price.$lte = parseFloat(maxPrice);
    }

    span.setAttribute('mongo.filter', JSON.stringify(filter));

    const products = await collection
      .find(filter)
      .project({ _id: 1, name: 1, price: 1, category: 1, stock: 1 })
      .limit(50)
      .toArray();

    span.setAttribute('db.documents_returned', products.length);
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

    res.json({
      products,
      count: products.length,
      filter,
      traceId: getTraceId(),
    });
  } catch (error) {
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
    res.status(500).json({ error: error.message, traceId: getTraceId() });
  } finally {
    span.end();
  }
});

// 6. MongoDB - Aggregation pipeline
app.get('/api/mongo/sales-report', async (req, res) => {
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const span = tracer.startSpan('mongo.sales_aggregation');

  try {
    const db = await connectMongo();
    const collection = db.collection('orders');

    const pipeline = [
      {
        $match: {
          status: 'completed',
          created_at: { $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) } // Last 30 days
        }
      },
      {
        $group: {
          _id: { $dateToString: { format: '%Y-%m-%d', date: '$created_at' } },
          totalSales: { $sum: '$total' },
          orderCount: { $sum: 1 },
          avgOrderValue: { $avg: '$total' }
        }
      },
      { $sort: { _id: -1 } },
      { $limit: 30 }
    ];

    const report = await collection.aggregate(pipeline).toArray();

    span.setAttribute('report.days', report.length);
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

    res.json({
      report,
      traceId: getTraceId(),
    });
  } catch (error) {
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
    res.status(500).json({ error: error.message, traceId: getTraceId() });
  } finally {
    span.end();
  }
});

// 7. MongoDB - Update with upsert
app.put('/api/mongo/cart/:userId', async (req, res) => {
  const { userId } = req.params;
  const { items } = req.body;
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const span = tracer.startSpan('mongo.update_cart');
  span.setAttribute('user.id', userId);

  try {
    const db = await connectMongo();
    const collection = db.collection('carts');

    const result = await collection.updateOne(
      { userId },
      {
        $set: {
          items,
          updatedAt: new Date()
        },
        $setOnInsert: {
          userId,
          createdAt: new Date()
        }
      },
      { upsert: true }
    );

    span.setAttribute('mongo.upserted', result.upsertedCount > 0);
    span.setAttribute('mongo.modified', result.modifiedCount);
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

    res.json({
      updated: result.modifiedCount > 0,
      upserted: result.upsertedCount > 0,
      traceId: getTraceId(),
    });
  } catch (error) {
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
    res.status(500).json({ error: error.message, traceId: getTraceId() });
  } finally {
    span.end();
  }
});

// ============================================
// REDIS EXAMPLES
// ============================================

// Redis client
const redisClient = redis.createClient({
  host: process.env.REDIS_HOST || 'localhost',
  port: process.env.REDIS_PORT || 6379,
  password: process.env.REDIS_PASSWORD || undefined,
});

redisClient.on('error', (err) => console.error('Redis Client Error', err));

// Connect Redis (async)
(async () => {
  await redisClient.connect();
})();

// 8. Redis - Cache-aside pattern
app.get('/api/cache/user/:id', async (req, res) => {
  const { id } = req.params;
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const span = tracer.startSpan('cache.get_user');
  span.setAttribute('user.id', id);

  const cacheKey = `user:${id}`;

  try {
    // Try to get from cache first
    const cached = await redisClient.get(cacheKey);

    if (cached) {
      span.setAttribute('cache.hit', true);
      span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

      res.json({
        user: JSON.parse(cached),
        source: 'cache',
        traceId: getTraceId(),
      });
      span.end();
      return;
    }

    span.setAttribute('cache.hit', false);

    // Cache miss - fetch from database
    const result = await pgPool.query('SELECT * FROM users WHERE id = $1', [id]);

    if (result.rows.length === 0) {
      span.setStatus({ code: opentelemetry.SpanStatusCode.OK });
      res.status(404).json({ error: 'User not found', traceId: getTraceId() });
      span.end();
      return;
    }

    const user = result.rows[0];

    // Store in cache for 5 minutes
    await redisClient.setEx(cacheKey, 300, JSON.stringify(user));

    span.setAttribute('cache.stored', true);
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

    res.json({
      user,
      source: 'database',
      traceId: getTraceId(),
    });
  } catch (error) {
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
    res.status(500).json({ error: error.message, traceId: getTraceId() });
  } finally {
    span.end();
  }
});

// 9. Redis - Rate limiting
app.get('/api/rate-limited/resource', async (req, res) => {
  const clientIp = req.ip;
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const span = tracer.startSpan('rate_limit.check');
  span.setAttribute('client.ip', clientIp);

  const rateLimitKey = `rate:${clientIp}`;
  const maxRequests = 10;
  const windowSeconds = 60;

  try {
    const current = await redisClient.incr(rateLimitKey);

    if (current === 1) {
      await redisClient.expire(rateLimitKey, windowSeconds);
    }

    const ttl = await redisClient.ttl(rateLimitKey);

    span.setAttribute('rate_limit.current', current);
    span.setAttribute('rate_limit.max', maxRequests);
    span.setAttribute('rate_limit.remaining', Math.max(0, maxRequests - current));

    if (current > maxRequests) {
      span.setAttribute('rate_limit.exceeded', true);
      span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

      res.status(429).json({
        error: 'Rate limit exceeded',
        retryAfter: ttl,
        traceId: getTraceId(),
      });
      span.end();
      return;
    }

    span.setAttribute('rate_limit.exceeded', false);
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

    res.set('X-RateLimit-Limit', maxRequests);
    res.set('X-RateLimit-Remaining', maxRequests - current);
    res.set('X-RateLimit-Reset', Date.now() + (ttl * 1000));

    res.json({
      message: 'Request successful',
      rateLimit: {
        limit: maxRequests,
        remaining: maxRequests - current,
        reset: ttl
      },
      traceId: getTraceId(),
    });
  } catch (error) {
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
    res.status(500).json({ error: error.message, traceId: getTraceId() });
  } finally {
    span.end();
  }
});

// ============================================
// EXTERNAL API CALLS (HTTP CLIENT)
// ============================================

// 10. Axios - Multiple parallel API calls
app.get('/api/external/user-dashboard/:userId', async (req, res) => {
  const { userId } = req.params;
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const span = tracer.startSpan('external.fetch_user_dashboard');
  span.setAttribute('user.id', userId);

  try {
    // Make multiple parallel API calls
    const [userProfile, userPosts, userTodos] = await Promise.all([
      axios.get(`https://jsonplaceholder.typicode.com/users/${userId}`),
      axios.get(`https://jsonplaceholder.typicode.com/posts?userId=${userId}`),
      axios.get(`https://jsonplaceholder.typicode.com/todos?userId=${userId}`),
    ]);

    span.setAttribute('api.calls_completed', 3);
    span.setAttribute('user.posts_count', userPosts.data.length);
    span.setAttribute('user.todos_count', userTodos.data.length);
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

    res.json({
      user: userProfile.data,
      posts: userPosts.data,
      todos: userTodos.data,
      summary: {
        postsCount: userPosts.data.length,
        todosCount: userTodos.data.length,
        completedTodos: userTodos.data.filter(t => t.completed).length
      },
      traceId: getTraceId(),
    });
  } catch (error) {
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
    res.status(500).json({
      error: error.message,
      service: error.response?.config?.url,
      statusCode: error.response?.status,
      traceId: getTraceId()
    });
  } finally {
    span.end();
  }
});

// 11. Axios - POST request with retry logic
app.post('/api/external/notify', async (req, res) => {
  const { message, recipient } = req.body;
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const span = tracer.startSpan('external.send_notification');
  span.setAttribute('recipient', recipient);

  const maxRetries = 3;
  let attempt = 0;

  try {
    while (attempt < maxRetries) {
      attempt++;
      span.setAttribute('retry.attempt', attempt);

      try {
        const response = await axios.post(
          'https://jsonplaceholder.typicode.com/posts',
          {
            title: `Notification for ${recipient}`,
            body: message,
            userId: 1
          },
          {
            timeout: 5000,
            headers: {
              'Content-Type': 'application/json',
            }
          }
        );

        span.setAttribute('notification.success', true);
        span.setAttribute('notification.id', response.data.id);
        span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

        res.json({
          success: true,
          notificationId: response.data.id,
          attempts: attempt,
          traceId: getTraceId(),
        });
        return;
      } catch (error) {
        if (attempt >= maxRetries) {
          throw error;
        }
        // Wait before retry with exponential backoff
        await new Promise(resolve => setTimeout(resolve, Math.pow(2, attempt) * 1000));
      }
    }
  } catch (error) {
    span.setAttribute('notification.success', false);
    span.setAttribute('retry.exhausted', true);
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });
    res.status(500).json({
      error: error.message,
      attempts: attempt,
      traceId: getTraceId()
    });
  } finally {
    span.end();
  }
});

// ============================================
// COMPLEX MULTI-SERVICE WORKFLOW
// ============================================

// 12. Complex workflow - Order processing with multiple DB operations
app.post('/api/orders/process', async (req, res) => {
  const { userId, items } = req.body;
  const tracer = opentelemetry.trace.getTracer('node14-express-example');
  const span = tracer.startSpan('order.process_complete_workflow');
  span.setAttribute('user.id', userId);
  span.setAttribute('items.count', items.length);

  const pgClient = await pgPool.connect();

  try {
    await pgClient.query('BEGIN');

    // 1. Check user exists (PostgreSQL)
    const userResult = await pgClient.query('SELECT id, email FROM users WHERE id = $1', [userId]);
    if (userResult.rows.length === 0) {
      throw new Error('User not found');
    }
    const user = userResult.rows[0];

    // 2. Check inventory (MySQL)
    const [inventory] = await mysqlPool.execute(
      'SELECT id, stock FROM products WHERE id IN (?)',
      [items.map(i => i.productId)]
    );

    for (const item of items) {
      const product = inventory.find(p => p.id === item.productId);
      if (!product || product.stock < item.quantity) {
        throw new Error(`Insufficient stock for product ${item.productId}`);
      }
    }

    // 3. Calculate total and create order (PostgreSQL)
    const total = items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    const orderResult = await pgClient.query(
      'INSERT INTO orders(user_id, total, status, created_at) VALUES($1, $2, $3, NOW()) RETURNING id',
      [userId, total, 'pending']
    );
    const orderId = orderResult.rows[0].id;

    // 4. Update inventory (MySQL)
    const mysqlConn = await mysqlPool.getConnection();
    await mysqlConn.beginTransaction();

    for (const item of items) {
      await mysqlConn.execute(
        'UPDATE products SET stock = stock - ? WHERE id = ?',
        [item.quantity, item.productId]
      );
    }

    await mysqlConn.commit();
    mysqlConn.release();

    // 5. Store order details in MongoDB
    const db = await connectMongo();
    await db.collection('order_details').insertOne({
      orderId,
      userId,
      items,
      total,
      status: 'pending',
      createdAt: new Date()
    });

    // 6. Send notification via external API
    try {
      await axios.post('https://jsonplaceholder.typicode.com/posts', {
        title: 'Order Confirmation',
        body: `Order #${orderId} created for ${user.email}`,
        userId: 1
      });
    } catch (notificationError) {
      // Log but don't fail the order
      console.error('Notification failed:', notificationError.message);
    }

    // 7. Clear user's cart from Redis
    await redisClient.del(`cart:${userId}`);

    await pgClient.query('COMMIT');

    span.setAttribute('order.id', orderId);
    span.setAttribute('order.total', total);
    span.setAttribute('order.status', 'success');
    span.setStatus({ code: opentelemetry.SpanStatusCode.OK });

    res.status(201).json({
      success: true,
      orderId,
      total,
      items: items.length,
      traceId: getTraceId(),
    });
  } catch (error) {
    await pgClient.query('ROLLBACK');

    span.setAttribute('order.status', 'failed');
    span.recordException(error);
    span.setStatus({
      code: opentelemetry.SpanStatusCode.ERROR,
      message: error.message
    });

    res.status(500).json({
      error: error.message,
      traceId: getTraceId()
    });
  } finally {
    pgClient.release();
    span.end();
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    traceId: getTraceId(),
  });
});

// Start server
app.listen(port, () => {
  console.log('========================================');
  console.log(`Node 14 Database Examples Server`);
  console.log('========================================');
  console.log(`Server running on http://localhost:${port}`);
  console.log('');
  console.log('Database Endpoints:');
  console.log('  PostgreSQL:');
  console.log(`    GET  /api/pg/users`);
  console.log(`    POST /api/pg/users`);
  console.log('  MySQL:');
  console.log(`    GET  /api/mysql/orders/:userId`);
  console.log(`    POST /api/mysql/products/bulk`);
  console.log('  MongoDB:');
  console.log(`    GET  /api/mongo/products`);
  console.log(`    GET  /api/mongo/sales-report`);
  console.log(`    PUT  /api/mongo/cart/:userId`);
  console.log('  Redis:');
  console.log(`    GET  /api/cache/user/:id`);
  console.log(`    GET  /api/rate-limited/resource`);
  console.log('  External APIs:');
  console.log(`    GET  /api/external/user-dashboard/:userId`);
  console.log(`    POST /api/external/notify`);
  console.log('  Complex Workflow:');
  console.log(`    POST /api/orders/process`);
  console.log('========================================\n');
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, closing database connections...');
  await pgPool.end();
  await mysqlPool.end();
  if (mongoClient) {
    await mongoClient.close();
  }
  await redisClient.quit();
  process.exit(0);
});
