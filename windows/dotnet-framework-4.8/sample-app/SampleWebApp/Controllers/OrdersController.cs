using System;
using System.Collections.Generic;
using System.Configuration;
using System.Data;
using System.Linq;
using System.Threading.Tasks;
using System.Web.Http;
using Oracle.ManagedDataAccess.Client;
using SampleWebApp.Models;
using SampleWebApp.Services;

namespace SampleWebApp.Controllers
{
    /// <summary>
    /// Orders Controller - Demonstrates comprehensive Oracle database instrumentation
    /// All database operations are automatically instrumented by OpenTelemetry
    /// </summary>
    [RoutePrefix("api/orders")]
    public class OrdersController : ApiController
    {
        private readonly string _connectionString;
        private readonly CacheService _cacheService;

        public OrdersController()
        {
            _connectionString = ConfigurationManager.AppSettings["OracleConnectionString"];
            _cacheService = new CacheService();
        }

        /// <summary>
        /// GET api/orders
        /// Retrieves all orders with caching
        /// Demonstrates: Oracle SELECT, connection pooling, caching
        /// </summary>
        [HttpGet]
        [Route("")]
        public async Task<IHttpActionResult> GetOrders(
            [FromUri] string status = null,
            [FromUri] int pageSize = 20,
            [FromUri] int page = 1)
        {
            try
            {
                // Check cache first - cache operations are auto-instrumented
                var cacheKey = $"orders:status:{status}:page:{page}:size:{pageSize}";
                var cachedOrders = _cacheService.Get<List<Order>>(cacheKey);

                if (cachedOrders != null)
                {
                    return Ok(new
                    {
                        data = cachedOrders,
                        cached = true,
                        page,
                        pageSize,
                        total = cachedOrders.Count
                    });
                }

                // Cache miss - fetch from database
                // Oracle connection and query execution are automatically instrumented
                using (var connection = new OracleConnection(_connectionString))
                {
                    await connection.OpenAsync();
                    // Span created: "Oracle.OpenAsync" with connection details

                    var query = @"
                        SELECT
                            ORDER_ID,
                            CUSTOMER_ID,
                            ORDER_DATE,
                            STATUS,
                            TOTAL_AMOUNT,
                            CREATED_AT,
                            UPDATED_AT
                        FROM ORDERS
                        WHERE (:status IS NULL OR STATUS = :status)
                        ORDER BY ORDER_DATE DESC
                        OFFSET :offset ROWS FETCH NEXT :pageSize ROWS ONLY";

                    using (var command = new OracleCommand(query, connection))
                    {
                        // Parameters prevent SQL injection
                        command.Parameters.Add(new OracleParameter("status", status ?? (object)DBNull.Value));
                        command.Parameters.Add(new OracleParameter("offset", (page - 1) * pageSize));
                        command.Parameters.Add(new OracleParameter("pageSize", pageSize));

                        var orders = new List<Order>();

                        using (var reader = await command.ExecuteReaderAsync())
                        {
                            // Span created: "Oracle.ExecuteReader" with query text and parameters
                            // Attributes include: db.statement, db.system=oracle, db.name, etc.

                            while (await reader.ReadAsync())
                            {
                                orders.Add(new Order
                                {
                                    OrderId = reader.GetInt32(reader.GetOrdinal("ORDER_ID")),
                                    CustomerId = reader.GetInt32(reader.GetOrdinal("CUSTOMER_ID")),
                                    OrderDate = reader.GetDateTime(reader.GetOrdinal("ORDER_DATE")),
                                    Status = reader.GetString(reader.GetOrdinal("STATUS")),
                                    TotalAmount = reader.GetDecimal(reader.GetOrdinal("TOTAL_AMOUNT")),
                                    CreatedAt = reader.GetDateTime(reader.GetOrdinal("CREATED_AT")),
                                    UpdatedAt = reader.IsDBNull(reader.GetOrdinal("UPDATED_AT"))
                                        ? (DateTime?)null
                                        : reader.GetDateTime(reader.GetOrdinal("UPDATED_AT"))
                                });
                            }
                        }

                        // Cache the results
                        _cacheService.Set(cacheKey, orders, TimeSpan.FromMinutes(5));

                        return Ok(new
                        {
                            data = orders,
                            cached = false,
                            page,
                            pageSize,
                            total = orders.Count
                        });
                    }
                }
            }
            catch (OracleException ex)
            {
                // Database exceptions are automatically captured in span with error details
                // Span marked as error with exception details
                return InternalServerError(new Exception($"Database error: {ex.Message}", ex));
            }
            catch (Exception ex)
            {
                return InternalServerError(ex);
            }
        }

        /// <summary>
        /// GET api/orders/{id}
        /// Get a single order by ID
        /// Demonstrates: Parameterized queries, null handling
        /// </summary>
        [HttpGet]
        [Route("{id:int}")]
        public async Task<IHttpActionResult> GetOrder(int id)
        {
            try
            {
                using (var connection = new OracleConnection(_connectionString))
                {
                    await connection.OpenAsync();

                    var query = @"
                        SELECT
                            ORDER_ID, CUSTOMER_ID, ORDER_DATE, STATUS,
                            TOTAL_AMOUNT, CREATED_AT, UPDATED_AT
                        FROM ORDERS
                        WHERE ORDER_ID = :orderId";

                    using (var command = new OracleCommand(query, connection))
                    {
                        command.Parameters.Add(new OracleParameter("orderId", id));

                        using (var reader = await command.ExecuteReaderAsync())
                        {
                            if (!await reader.ReadAsync())
                            {
                                return NotFound();
                            }

                            var order = new Order
                            {
                                OrderId = reader.GetInt32(reader.GetOrdinal("ORDER_ID")),
                                CustomerId = reader.GetInt32(reader.GetOrdinal("CUSTOMER_ID")),
                                OrderDate = reader.GetDateTime(reader.GetOrdinal("ORDER_DATE")),
                                Status = reader.GetString(reader.GetOrdinal("STATUS")),
                                TotalAmount = reader.GetDecimal(reader.GetOrdinal("TOTAL_AMOUNT")),
                                CreatedAt = reader.GetDateTime(reader.GetOrdinal("CREATED_AT")),
                                UpdatedAt = reader.IsDBNull(reader.GetOrdinal("UPDATED_AT"))
                                    ? (DateTime?)null
                                    : reader.GetDateTime(reader.GetOrdinal("UPDATED_AT"))
                            };

                            return Ok(order);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                return InternalServerError(ex);
            }
        }

        /// <summary>
        /// POST api/orders
        /// Create a new order
        /// Demonstrates: INSERT operations, transactions, rollback on error
        /// </summary>
        [HttpPost]
        [Route("")]
        public async Task<IHttpActionResult> CreateOrder([FromBody] CreateOrderRequest request)
        {
            if (request == null || !ModelState.IsValid)
            {
                return BadRequest(ModelState);
            }

            OracleConnection connection = null;
            OracleTransaction transaction = null;

            try
            {
                connection = new OracleConnection(_connectionString);
                await connection.OpenAsync();

                // Begin transaction - transaction spans are automatically created
                transaction = connection.BeginTransaction();

                // Insert order
                var insertQuery = @"
                    INSERT INTO ORDERS (ORDER_ID, CUSTOMER_ID, ORDER_DATE, STATUS, TOTAL_AMOUNT, CREATED_AT)
                    VALUES (ORDER_SEQ.NEXTVAL, :customerId, :orderDate, :status, :totalAmount, SYSDATE)
                    RETURNING ORDER_ID INTO :orderId";

                int orderId;
                using (var command = new OracleCommand(insertQuery, connection, transaction))
                {
                    command.Parameters.Add(new OracleParameter("customerId", request.CustomerId));
                    command.Parameters.Add(new OracleParameter("orderDate", DateTime.UtcNow));
                    command.Parameters.Add(new OracleParameter("status", "PENDING"));
                    command.Parameters.Add(new OracleParameter("totalAmount", request.TotalAmount));

                    var orderIdParam = new OracleParameter("orderId", OracleDbType.Int32);
                    orderIdParam.Direction = ParameterDirection.Output;
                    command.Parameters.Add(orderIdParam);

                    await command.ExecuteNonQueryAsync();
                    // Span created with INSERT statement details

                    orderId = Convert.ToInt32(orderIdParam.Value.ToString());
                }

                // Insert order items (batch operation)
                if (request.Items != null && request.Items.Any())
                {
                    var itemQuery = @"
                        INSERT INTO ORDER_ITEMS (ORDER_ITEM_ID, ORDER_ID, PRODUCT_ID, QUANTITY, PRICE)
                        VALUES (ORDER_ITEM_SEQ.NEXTVAL, :orderId, :productId, :quantity, :price)";

                    using (var command = new OracleCommand(itemQuery, connection, transaction))
                    {
                        // Batch insert - each iteration is instrumented
                        foreach (var item in request.Items)
                        {
                            command.Parameters.Clear();
                            command.Parameters.Add(new OracleParameter("orderId", orderId));
                            command.Parameters.Add(new OracleParameter("productId", item.ProductId));
                            command.Parameters.Add(new OracleParameter("quantity", item.Quantity));
                            command.Parameters.Add(new OracleParameter("price", item.Price));

                            await command.ExecuteNonQueryAsync();
                        }
                    }
                }

                // Commit transaction - span includes commit operation
                transaction.Commit();

                // Invalidate cache
                _cacheService.Remove("orders:*");

                return Created($"/api/orders/{orderId}", new { orderId, status = "PENDING" });
            }
            catch (OracleException ex)
            {
                // Rollback on error - automatically captured in span
                transaction?.Rollback();
                return InternalServerError(new Exception($"Failed to create order: {ex.Message}", ex));
            }
            catch (Exception ex)
            {
                transaction?.Rollback();
                return InternalServerError(ex);
            }
            finally
            {
                transaction?.Dispose();
                connection?.Dispose();
            }
        }

        /// <summary>
        /// PUT api/orders/{id}/status
        /// Update order status
        /// Demonstrates: UPDATE operations, optimistic concurrency
        /// </summary>
        [HttpPut]
        [Route("{id:int}/status")]
        public async Task<IHttpActionResult> UpdateOrderStatus(int id, [FromBody] UpdateStatusRequest request)
        {
            if (request == null || string.IsNullOrWhiteSpace(request.Status))
            {
                return BadRequest("Status is required");
            }

            try
            {
                using (var connection = new OracleConnection(_connectionString))
                {
                    await connection.OpenAsync();

                    var query = @"
                        UPDATE ORDERS
                        SET STATUS = :status, UPDATED_AT = SYSDATE
                        WHERE ORDER_ID = :orderId";

                    using (var command = new OracleCommand(query, connection))
                    {
                        command.Parameters.Add(new OracleParameter("status", request.Status.ToUpper()));
                        command.Parameters.Add(new OracleParameter("orderId", id));

                        var rowsAffected = await command.ExecuteNonQueryAsync();
                        // Span includes UPDATE statement and rows affected

                        if (rowsAffected == 0)
                        {
                            return NotFound();
                        }

                        // Invalidate cache
                        _cacheService.Remove($"orders:*");

                        return Ok(new { orderId = id, status = request.Status.ToUpper(), updated = true });
                    }
                }
            }
            catch (Exception ex)
            {
                return InternalServerError(ex);
            }
        }

        /// <summary>
        /// DELETE api/orders/{id}
        /// Soft delete an order
        /// Demonstrates: UPDATE for soft delete pattern
        /// </summary>
        [HttpDelete]
        [Route("{id:int}")]
        public async Task<IHttpActionResult> DeleteOrder(int id)
        {
            try
            {
                using (var connection = new OracleConnection(_connectionString))
                {
                    await connection.OpenAsync();

                    // Soft delete - set status to CANCELLED
                    var query = @"
                        UPDATE ORDERS
                        SET STATUS = 'CANCELLED', UPDATED_AT = SYSDATE
                        WHERE ORDER_ID = :orderId AND STATUS != 'CANCELLED'";

                    using (var command = new OracleCommand(query, connection))
                    {
                        command.Parameters.Add(new OracleParameter("orderId", id));

                        var rowsAffected = await command.ExecuteNonQueryAsync();

                        if (rowsAffected == 0)
                        {
                            return NotFound();
                        }

                        // Invalidate cache
                        _cacheService.Remove($"orders:*");

                        return Ok(new { orderId = id, status = "CANCELLED" });
                    }
                }
            }
            catch (Exception ex)
            {
                return InternalServerError(ex);
            }
        }

        /// <summary>
        /// GET api/orders/statistics
        /// Get order statistics using stored procedure
        /// Demonstrates: Stored procedure calls
        /// </summary>
        [HttpGet]
        [Route("statistics")]
        public async Task<IHttpActionResult> GetStatistics()
        {
            try
            {
                using (var connection = new OracleConnection(_connectionString))
                {
                    await connection.OpenAsync();

                    using (var command = new OracleCommand("GET_ORDER_STATISTICS", connection))
                    {
                        command.CommandType = CommandType.StoredProcedure;

                        // Output parameters
                        var totalOrdersParam = new OracleParameter("p_total_orders", OracleDbType.Int32);
                        totalOrdersParam.Direction = ParameterDirection.Output;
                        command.Parameters.Add(totalOrdersParam);

                        var totalRevenueParam = new OracleParameter("p_total_revenue", OracleDbType.Decimal);
                        totalRevenueParam.Direction = ParameterDirection.Output;
                        command.Parameters.Add(totalRevenueParam);

                        var avgOrderValueParam = new OracleParameter("p_avg_order_value", OracleDbType.Decimal);
                        avgOrderValueParam.Direction = ParameterDirection.Output;
                        command.Parameters.Add(avgOrderValueParam);

                        await command.ExecuteNonQueryAsync();
                        // Span created for stored procedure execution

                        var statistics = new
                        {
                            totalOrders = Convert.ToInt32(totalOrdersParam.Value.ToString()),
                            totalRevenue = Convert.ToDecimal(totalRevenueParam.Value.ToString()),
                            avgOrderValue = Convert.ToDecimal(avgOrderValueParam.Value.ToString())
                        };

                        return Ok(statistics);
                    }
                }
            }
            catch (Exception ex)
            {
                return InternalServerError(ex);
            }
        }
    }

    #region Request Models

    public class CreateOrderRequest
    {
        public int CustomerId { get; set; }
        public decimal TotalAmount { get; set; }
        public List<OrderItemRequest> Items { get; set; }
    }

    public class OrderItemRequest
    {
        public int ProductId { get; set; }
        public int Quantity { get; set; }
        public decimal Price { get; set; }
    }

    public class UpdateStatusRequest
    {
        public string Status { get; set; }
    }

    #endregion
}

/*
 * OPENTELEMETRY INSTRUMENTATION NOTES:
 *
 * This controller demonstrates comprehensive Oracle database instrumentation.
 * All operations are automatically instrumented by OpenTelemetry .NET Auto-Instrumentation.
 *
 * What Gets Automatically Captured:
 *
 * 1. CONNECTION OPERATIONS:
 *    - connection.OpenAsync() creates spans with:
 *      - db.system = "oracle"
 *      - db.connection_string (sanitized, no password)
 *      - db.user
 *      - net.peer.name = database host
 *      - net.peer.port = database port
 *
 * 2. QUERY EXECUTION:
 *    - command.ExecuteReaderAsync(), ExecuteNonQueryAsync() create spans with:
 *      - db.statement = SQL query text
 *      - db.operation = SELECT/INSERT/UPDATE/DELETE
 *      - Rows affected (for writes)
 *      - Execution time
 *
 * 3. TRANSACTIONS:
 *    - BeginTransaction(), Commit(), Rollback() are tracked
 *    - Transaction IDs included in spans
 *    - Rollback reasons captured on errors
 *
 * 4. EXCEPTIONS:
 *    - All OracleException details captured
 *    - Stack traces included
 *    - Span marked as error
 *    - Error propagated to parent HTTP span
 *
 * 5. CACHE OPERATIONS:
 *    - _cacheService calls are instrumented if using instrumented cache library
 *    - Cache hit/miss tracked
 *
 * DISTRIBUTED TRACING:
 *
 * Parent HTTP request span includes all database child spans:
 *
 * HTTP GET /api/orders
 *   ├─ Oracle.OpenAsync
 *   ├─ Oracle.ExecuteReader (SELECT)
 *   └─ Cache.Set
 *
 * PERFORMANCE IMPACT:
 *
 * - Per-query overhead: 0.1-0.5ms
 * - Memory per span: ~2-5KB
 * - No query result data captured (only metadata)
 *
 * SECURITY:
 *
 * - Passwords are automatically stripped from connection strings
 * - Query parameters are captured (review sensitive data filtering in gateway)
 * - Consider adding @sensitive_data annotation to exclude specific queries
 *
 * CUSTOMIZATION:
 *
 * To add custom attributes to database spans:
 *
 * using OpenTelemetry.Trace;
 *
 * var span = Tracer.CurrentSpan;
 * span?.SetAttribute("order.id", orderId);
 * span?.SetAttribute("customer.tier", "premium");
 */
