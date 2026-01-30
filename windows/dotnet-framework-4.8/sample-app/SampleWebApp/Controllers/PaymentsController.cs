using System;
using System.Collections.Generic;
using System.Configuration;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using System.Web.Http;
using Newtonsoft.Json;
using SampleWebApp.Models;
using SampleWebApp.Services;

namespace SampleWebApp.Controllers
{
    /// <summary>
    /// Payments Controller - Demonstrates comprehensive HTTP client instrumentation
    /// All outbound HTTP requests are automatically instrumented by OpenTelemetry
    /// Shows distributed tracing with external services
    /// </summary>
    [RoutePrefix("api/payments")]
    public class PaymentsController : ApiController
    {
        // Static HttpClient for connection pooling (best practice)
        private static readonly HttpClient _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(30)
        };

        private readonly string _paymentGatewayUrl;
        private readonly CacheService _cacheService;

        public PaymentsController()
        {
            _paymentGatewayUrl = ConfigurationManager.AppSettings["PaymentGatewayUrl"]
                ?? "https://api.payment-gateway.example.com";
            _cacheService = new CacheService();
        }

        /// <summary>
        /// POST api/payments/process
        /// Process a payment through external gateway
        /// Demonstrates: HTTP POST with body, distributed tracing, error handling
        /// </summary>
        [HttpPost]
        [Route("process")]
        public async Task<IHttpActionResult> ProcessPayment([FromBody] PaymentRequest request)
        {
            if (request == null || !ModelState.IsValid)
            {
                return BadRequest(ModelState);
            }

            try
            {
                // Prepare payment request
                var gatewayRequest = new
                {
                    amount = request.Amount,
                    currency = request.Currency ?? "USD",
                    cardNumber = request.CardNumber,
                    cardholderName = request.CardholderName,
                    expiryMonth = request.ExpiryMonth,
                    expiryYear = request.ExpiryYear,
                    cvv = request.CVV,
                    orderId = request.OrderId,
                    description = request.Description
                };

                var jsonContent = JsonConvert.SerializeObject(gatewayRequest);
                var httpContent = new StringContent(jsonContent, Encoding.UTF8, "application/json");

                // Make HTTP request - automatically instrumented!
                // Creates span with:
                // - http.method = POST
                // - http.url = full URL
                // - http.status_code = response status
                // - http.request.body.size
                // - http.response.body.size
                // - Distributed trace context propagated via headers (W3C TraceContext)
                var response = await _httpClient.PostAsync(
                    $"{_paymentGatewayUrl}/v1/charges",
                    httpContent
                );

                var responseContent = await response.Content.ReadAsStringAsync();

                if (response.IsSuccessStatusCode)
                {
                    var paymentResult = JsonConvert.DeserializeObject<PaymentResult>(responseContent);

                    // Cache successful transaction
                    _cacheService.Set($"payment:{paymentResult.TransactionId}", paymentResult, TimeSpan.FromHours(24));

                    return Ok(new
                    {
                        success = true,
                        transactionId = paymentResult.TransactionId,
                        status = paymentResult.Status,
                        amount = paymentResult.Amount,
                        currency = paymentResult.Currency
                    });
                }
                else
                {
                    // Error responses are automatically captured in span
                    // Span marked with error status
                    var errorResponse = JsonConvert.DeserializeObject<PaymentError>(responseContent);

                    return Content(
                        response.StatusCode,
                        new
                        {
                            success = false,
                            error = errorResponse.Message,
                            code = errorResponse.Code
                        }
                    );
                }
            }
            catch (HttpRequestException ex)
            {
                // Network errors automatically captured
                // Span includes exception details
                return InternalServerError(new Exception($"Payment gateway unreachable: {ex.Message}", ex));
            }
            catch (TaskCanceledException ex)
            {
                // Timeout errors automatically captured
                return InternalServerError(new Exception("Payment request timed out", ex));
            }
            catch (Exception ex)
            {
                return InternalServerError(ex);
            }
        }

        /// <summary>
        /// GET api/payments/{transactionId}
        /// Check payment status
        /// Demonstrates: HTTP GET with headers, caching, retry logic
        /// </summary>
        [HttpGet]
        [Route("{transactionId}")]
        public async Task<IHttpActionResult> GetPaymentStatus(string transactionId)
        {
            try
            {
                // Check cache first - cache operations are instrumented
                var cachedResult = _cacheService.Get<PaymentResult>($"payment:{transactionId}");
                if (cachedResult != null)
                {
                    return Ok(new
                    {
                        transactionId = cachedResult.TransactionId,
                        status = cachedResult.Status,
                        amount = cachedResult.Amount,
                        cached = true
                    });
                }

                // Cache miss - query payment gateway
                var request = new HttpRequestMessage(HttpMethod.Get, $"{_paymentGatewayUrl}/v1/charges/{transactionId}");

                // Add custom headers - these are included in trace
                request.Headers.Add("X-API-Version", "2024-01");
                request.Headers.Add("X-Client-Id", "dotnet-sample-app");

                // Retry logic with exponential backoff
                PaymentResult result = null;
                int retries = 3;
                int delayMs = 1000;

                for (int attempt = 1; attempt <= retries; attempt++)
                {
                    try
                    {
                        // Each retry creates a separate HTTP span
                        var response = await _httpClient.SendAsync(request);

                        if (response.IsSuccessStatusCode)
                        {
                            var content = await response.Content.ReadAsStringAsync();
                            result = JsonConvert.DeserializeObject<PaymentResult>(content);
                            break;
                        }
                        else if (response.StatusCode == HttpStatusCode.TooManyRequests && attempt < retries)
                        {
                            // Rate limited - wait and retry
                            await Task.Delay(delayMs);
                            delayMs *= 2; // Exponential backoff
                        }
                        else
                        {
                            // Non-retryable error
                            return Content(response.StatusCode, new { error = "Payment not found or gateway error" });
                        }
                    }
                    catch (Exception ex) when (attempt < retries)
                    {
                        // Transient error - wait and retry
                        await Task.Delay(delayMs);
                        delayMs *= 2;
                    }
                }

                if (result == null)
                {
                    return NotFound();
                }

                // Cache for future requests
                _cacheService.Set($"payment:{transactionId}", result, TimeSpan.FromMinutes(5));

                return Ok(new
                {
                    transactionId = result.TransactionId,
                    status = result.Status,
                    amount = result.Amount,
                    cached = false
                });
            }
            catch (Exception ex)
            {
                return InternalServerError(ex);
            }
        }

        /// <summary>
        /// POST api/payments/{transactionId}/refund
        /// Refund a payment
        /// Demonstrates: HTTP POST with path parameters, authorization headers
        /// </summary>
        [HttpPost]
        [Route("{transactionId}/refund")]
        public async Task<IHttpActionResult> RefundPayment(string transactionId, [FromBody] RefundRequest request)
        {
            if (request == null)
            {
                return BadRequest("Refund request is required");
            }

            try
            {
                var refundData = new
                {
                    transactionId,
                    amount = request.Amount,
                    reason = request.Reason
                };

                var jsonContent = JsonConvert.SerializeObject(refundData);
                var httpContent = new StringContent(jsonContent, Encoding.UTF8, "application/json");

                var httpRequest = new HttpRequestMessage(HttpMethod.Post, $"{_paymentGatewayUrl}/v1/refunds")
                {
                    Content = httpContent
                };

                // Add authorization header (will be automatically captured but sanitized)
                httpRequest.Headers.Add("Authorization", $"Bearer {GetApiKey()}");

                // Make request - span includes auth header (sanitized in gateway config)
                var response = await _httpClient.SendAsync(httpRequest);
                var responseContent = await response.Content.ReadAsStringAsync();

                if (response.IsSuccessStatusCode)
                {
                    var refundResult = JsonConvert.DeserializeObject<RefundResult>(responseContent);

                    // Invalidate payment cache
                    _cacheService.Remove($"payment:{transactionId}");

                    return Ok(new
                    {
                        success = true,
                        refundId = refundResult.RefundId,
                        transactionId,
                        amount = refundResult.Amount,
                        status = refundResult.Status
                    });
                }
                else
                {
                    return Content(response.StatusCode, new { error = "Refund failed", details = responseContent });
                }
            }
            catch (Exception ex)
            {
                return InternalServerError(ex);
            }
        }

        /// <summary>
        /// GET api/payments/batch-status
        /// Check status of multiple payments
        /// Demonstrates: Parallel HTTP requests, task aggregation
        /// </summary>
        [HttpGet]
        [Route("batch-status")]
        public async Task<IHttpActionResult> GetBatchStatus([FromUri] string[] transactionIds)
        {
            if (transactionIds == null || transactionIds.Length == 0)
            {
                return BadRequest("Transaction IDs are required");
            }

            try
            {
                // Create parallel tasks - each creates its own HTTP span
                var tasks = new List<Task<PaymentStatusResponse>>();

                foreach (var txId in transactionIds)
                {
                    tasks.Add(GetSinglePaymentStatusAsync(txId));
                }

                // Wait for all requests to complete
                // Parent span includes all child HTTP spans
                var results = await Task.WhenAll(tasks);

                return Ok(new
                {
                    count = results.Length,
                    payments = results
                });
            }
            catch (Exception ex)
            {
                return InternalServerError(ex);
            }
        }

        /// <summary>
        /// POST api/payments/webhook
        /// Receive payment gateway webhook
        /// Demonstrates: Inbound HTTP from external service, correlation
        /// </summary>
        [HttpPost]
        [Route("webhook")]
        public async Task<IHttpActionResult> PaymentWebhook([FromBody] PaymentWebhook webhook)
        {
            if (webhook == null)
            {
                return BadRequest("Webhook payload required");
            }

            try
            {
                // Verify webhook signature (in production)
                // var isValid = VerifyWebhookSignature(Request.Headers.GetValues("X-Signature").FirstOrDefault(), webhook);
                // if (!isValid) return Unauthorized();

                // Process webhook asynchronously
                // This would typically queue a background job
                await Task.Run(() => ProcessWebhookAsync(webhook));

                // Invalidate cache for this transaction
                _cacheService.Remove($"payment:{webhook.TransactionId}");

                return Ok(new { received = true });
            }
            catch (Exception ex)
            {
                return InternalServerError(ex);
            }
        }

        #region Helper Methods

        private async Task<PaymentStatusResponse> GetSinglePaymentStatusAsync(string transactionId)
        {
            try
            {
                // Each call creates its own HTTP client span
                var response = await _httpClient.GetAsync($"{_paymentGatewayUrl}/v1/charges/{transactionId}");

                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    var result = JsonConvert.DeserializeObject<PaymentResult>(content);

                    return new PaymentStatusResponse
                    {
                        TransactionId = transactionId,
                        Status = result.Status,
                        Amount = result.Amount,
                        Success = true
                    };
                }
                else
                {
                    return new PaymentStatusResponse
                    {
                        TransactionId = transactionId,
                        Success = false,
                        Error = $"HTTP {(int)response.StatusCode}"
                    };
                }
            }
            catch (Exception ex)
            {
                return new PaymentStatusResponse
                {
                    TransactionId = transactionId,
                    Success = false,
                    Error = ex.Message
                };
            }
        }

        private async Task ProcessWebhookAsync(PaymentWebhook webhook)
        {
            // Simulate webhook processing
            // In production, this would update database, send notifications, etc.
            await Task.Delay(100);

            // Log webhook event (automatically captured if using ILogger)
            System.Diagnostics.Trace.TraceInformation(
                $"Webhook processed: {webhook.TransactionId}, Status: {webhook.Status}"
            );
        }

        private string GetApiKey()
        {
            // In production, use secure configuration or key vault
            return ConfigurationManager.AppSettings["PaymentGatewayApiKey"] ?? "test_key";
        }

        #endregion
    }

    #region Request/Response Models

    public class PaymentStatusResponse
    {
        public string TransactionId { get; set; }
        public string Status { get; set; }
        public decimal Amount { get; set; }
        public bool Success { get; set; }
        public string Error { get; set; }
    }

    #endregion
}

/*
 * OPENTELEMETRY HTTP CLIENT INSTRUMENTATION NOTES:
 *
 * This controller demonstrates comprehensive HTTP client instrumentation.
 * All outbound HTTP requests are automatically instrumented by OpenTelemetry.
 *
 * What Gets Automatically Captured:
 *
 * 1. REQUEST DETAILS:
 *    - http.method = GET/POST/PUT/DELETE
 *    - http.url = full URL (query params included, sanitized)
 *    - http.scheme = http/https
 *    - http.host = hostname:port
 *    - http.target = path
 *    - http.user_agent = client user agent
 *    - http.request_content_length = request size
 *
 * 2. RESPONSE DETAILS:
 *    - http.status_code = 200/404/500/etc
 *    - http.response_content_length = response size
 *    - Duration (automatic timing)
 *
 * 3. DISTRIBUTED TRACING:
 *    - W3C TraceContext headers automatically added to outgoing requests
 *    - traceparent: version-trace_id-span_id-flags
 *    - tracestate: vendor-specific state
 *    - Enables end-to-end tracing across services
 *
 * 4. ERROR HANDLING:
 *    - HttpRequestException captured (network errors)
 *    - TaskCanceledException captured (timeouts)
 *    - Non-2xx status codes marked as errors
 *    - Exception details in span
 *
 * 5. RETRY LOGIC:
 *    - Each retry attempt creates a new span
 *    - Parent span includes all retry child spans
 *    - Allows analysis of retry patterns
 *
 * DISTRIBUTED TRACING FLOW:
 *
 * Incoming HTTP Request to PaymentsController
 *   ├─ ASP.NET span (auto-created)
 *   ├─ Cache check span (if instrumented)
 *   ├─ HTTP Client POST to /v1/charges
 *   │   ├─ Request headers include traceparent
 *   │   ├─ Payment gateway receives trace context
 *   │   └─ Gateway creates child spans (if instrumented)
 *   └─ Cache set span
 *
 * SECURITY CONSIDERATIONS:
 *
 * - Sensitive headers are automatically sanitized:
 *   - Authorization headers value replaced with "[REDACTED]"
 *   - API keys in headers sanitized
 *   - Passwords in URLs removed
 *
 * - To add custom sanitization in datacenter gateway:
 *   processors:
 *     attributes:
 *       actions:
 *         - key: http.request.header.authorization
 *           action: delete
 *
 * PERFORMANCE IMPACT:
 *
 * - Per HTTP request overhead: 0.1-0.5ms
 *   - Header injection: ~0.05ms
 *   - Span creation: ~0.1ms
 *   - Metadata collection: ~0.05ms
 *
 * - Memory per span: ~3-5KB
 *   - Includes all HTTP metadata
 *   - Request/response bodies NOT captured (only sizes)
 *
 * BEST PRACTICES:
 *
 * 1. Use static HttpClient for connection pooling
 *    ✓ private static readonly HttpClient _httpClient = new HttpClient();
 *    ✗ var client = new HttpClient(); // Creates new connections
 *
 * 2. Set reasonable timeouts
 *    _httpClient.Timeout = TimeSpan.FromSeconds(30);
 *
 * 3. Use async/await for all HTTP operations
 *    ✓ await _httpClient.GetAsync(url);
 *    ✗ _httpClient.GetAsync(url).Result; // Blocks thread
 *
 * 4. Handle transient errors with retry logic
 *    - Use exponential backoff
 *    - Limit retry attempts
 *    - Log retry events
 *
 * 5. Add custom attributes to spans when needed:
 *    using OpenTelemetry.Trace;
 *    var span = Tracer.CurrentSpan;
 *    span?.SetAttribute("payment.gateway", "stripe");
 *    span?.SetAttribute("payment.amount", amount);
 *
 * TROUBLESHOOTING:
 *
 * - No HTTP client spans appearing:
 *   Check OTEL_DOTNET_AUTO_INSTRUMENTATION_HTTPCLIENT_ENABLED=true
 *
 * - Distributed tracing not working:
 *   Verify downstream service supports W3C TraceContext headers
 *
 * - High span volume:
 *   Consider sampling at gateway level (tail sampling)
 */
