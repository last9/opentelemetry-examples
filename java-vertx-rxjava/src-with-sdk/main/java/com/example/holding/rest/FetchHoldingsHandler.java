package com.example.holding.rest;

import com.example.holding.dto.GetAllHoldingsResponse;
import com.example.holding.services.GraphQLService;
import com.example.holding.services.HoldingService;
import io.otel.rxjava.vertx.context.VertxTracing;
import io.otel.rxjava.vertx.logging.MdcTraceCorrelation;
import io.vertx.core.json.Json;
import io.vertx.rxjava3.ext.web.RoutingContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.Map;

/**
 * REST endpoint for fetching holdings with proper tracing.
 *
 * Changes from original:
 * 1. Call MdcTraceCorrelation.updateMdc() at handler entry for log correlation
 * 2. Add attributes to the HTTP span using VertxTracing.addAttributes()
 * 3. Context automatically propagates through flatMap to child service spans
 * 4. All logs within this request will have the same trace_id
 */
public class FetchHoldingsHandler {
    private static final Logger log = LoggerFactory.getLogger(FetchHoldingsHandler.class);
    private static final String AUTH_HEADER_USER_ID = "X-User-Id";

    private final HoldingService holdingService;
    private final GraphQLService graphQLService;

    public FetchHoldingsHandler(HoldingService holdingService, GraphQLService graphQLService) {
        this.holdingService = holdingService;
        this.graphQLService = graphQLService;
    }

    public void fetchAllHoldings(RoutingContext ctx) {
        // Step 1: Update MDC with trace context for log correlation
        // This ensures all logs in this handler have trace_id and span_id
        MdcTraceCorrelation.updateMdc();

        String userId = ctx.request().getHeader(AUTH_HEADER_USER_ID);
        String tradingType = ctx.request().getParam("trading_type");
        String symbol = ctx.request().getParam("symbol");

        // Step 2: Add custom attributes to the HTTP span
        VertxTracing.addAttributes(Map.of(
                "user.id", userId != null ? userId : "unknown",
                "request.trading_type", tradingType != null ? tradingType : "all",
                "request.symbol", symbol != null ? symbol : "all"
        ));

        if (userId == null || userId.isEmpty()) {
            log.warn("Request rejected: missing userId header");
            ctx.response()
                    .setStatusCode(400)
                    .putHeader("Content-Type", "application/json")
                    .end(Json.encode(new ErrorResponse("400", "userId cannot be null")));
            return;
        }

        // This log will include trace_id and span_id
        log.info("Received fetchAllHoldings request for userId: {}, tradingType: {}, symbol: {}",
                userId, tradingType, symbol);

        List<String> tradingTypes = holdingService.parseTradingTypes(tradingType);

        // Step 3: Chain service calls - context propagates automatically
        // Each service creates a child span via Traced.call()
        // The trace hierarchy will be:
        //   HTTP GET /v1/holding (parent)
        //   ├── HoldingService.fetchHoldings (child)
        //   └── GraphQLService.enrichHoldings (child)
        holdingService.fetchAllHoldingsByUserIdAndTradingTypes(userId, tradingTypes, symbol)
                .flatMap(response -> {
                    // Context is preserved here due to RxJava3ContextPropagation
                    if (response != null && response.getHoldings() != null && !response.getHoldings().isEmpty()) {
                        return graphQLService.enrichHoldingsWithScripDetails(response.getHoldings())
                                .map(enrichedHoldings -> {
                                    response.setHoldings(enrichedHoldings);
                                    int holdingsCount = enrichedHoldings.size();

                                    // Add event to span
                                    VertxTracing.addEvent("holdings.enriched",
                                            Map.of("count", holdingsCount));

                                    log.info("Successfully processed request for userId: {}, holdingsCount: {}",
                                            userId, holdingsCount);
                                    return response;
                                })
                                .onErrorResumeNext(error -> {
                                    log.warn("Failed to enrich holdings, returning original response", error);
                                    VertxTracing.addEvent("enrichment.failed",
                                            Map.of("error", error.getMessage()));
                                    return io.reactivex.rxjava3.core.Single.just(response);
                                });
                    }
                    return io.reactivex.rxjava3.core.Single.just(response);
                })
                .subscribe(
                        response -> {
                            // Update MDC again in subscribe callback (different thread)
                            MdcTraceCorrelation.updateMdc();
                            ctx.response()
                                    .setStatusCode(200)
                                    .putHeader("Content-Type", "application/json")
                                    .end(Json.encode(response));
                        },
                        error -> {
                            MdcTraceCorrelation.updateMdc();
                            log.error("Error fetching holdings for userId: {}", userId, error);

                            // Record exception on span
                            VertxTracing.recordException(error);

                            ctx.response()
                                    .setStatusCode(500)
                                    .putHeader("Content-Type", "application/json")
                                    .end(Json.encode(new ErrorResponse("500", "Internal server error")));
                        }
                );
    }

    private static class ErrorResponse {
        public String responseCode;
        public String description;

        public ErrorResponse(String responseCode, String description) {
            this.responseCode = responseCode;
            this.description = description;
        }
    }
}
