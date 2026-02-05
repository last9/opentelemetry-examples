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
 * REST endpoint for fetching holdings with proper tracing and log correlation.
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

    /**
     * Fetch holdings from mock data (original endpoint)
     */
    public void fetchAllHoldings(RoutingContext ctx) {
        MdcTraceCorrelation.updateMdc();

        String userId = ctx.request().getHeader(AUTH_HEADER_USER_ID);
        String tradingType = ctx.request().getParam("trading_type");
        String symbol = ctx.request().getParam("symbol");

        VertxTracing.addAttributes(Map.of(
                "user.id", userId != null ? userId : "unknown",
                "request.trading_type", tradingType != null ? tradingType : "all",
                "request.symbol", symbol != null ? symbol : "all",
                "data.source", "mock"
        ));

        if (userId == null || userId.isEmpty()) {
            log.warn("Request rejected: missing userId header");
            ctx.response()
                    .setStatusCode(400)
                    .putHeader("Content-Type", "application/json")
                    .end(Json.encode(new ErrorResponse("400", "userId cannot be null")));
            return;
        }

        log.info("Received fetchAllHoldings request for userId: {}, tradingType: {}, symbol: {}",
                userId, tradingType, symbol);

        List<String> tradingTypes = holdingService.parseTradingTypes(tradingType);

        holdingService.fetchAllHoldingsByUserIdAndTradingTypes(userId, tradingTypes, symbol)
                .flatMap(response -> {
                    if (response != null && response.getHoldings() != null && !response.getHoldings().isEmpty()) {
                        return graphQLService.enrichHoldingsWithScripDetails(response.getHoldings())
                                .map(enrichedHoldings -> {
                                    response.setHoldings(enrichedHoldings);
                                    int holdingsCount = enrichedHoldings.size();
                                    VertxTracing.addEvent("holdings.enriched", Map.of("count", holdingsCount));
                                    log.info("Successfully processed request for userId: {}, holdingsCount: {}",
                                            userId, holdingsCount);
                                    return response;
                                })
                                .onErrorResumeNext(error -> {
                                    log.warn("Failed to enrich holdings, returning original response", error);
                                    VertxTracing.addEvent("enrichment.failed", Map.of("error", error.getMessage()));
                                    return io.reactivex.rxjava3.core.Single.just(response);
                                });
                    }
                    return io.reactivex.rxjava3.core.Single.just(response);
                })
                .subscribe(
                        response -> {
                            MdcTraceCorrelation.updateMdc();
                            ctx.response()
                                    .setStatusCode(200)
                                    .putHeader("Content-Type", "application/json")
                                    .end(Json.encode(response));
                        },
                        error -> {
                            MdcTraceCorrelation.updateMdc();
                            log.error("Error fetching holdings for userId: {}", userId, error);
                            VertxTracing.recordException(error);
                            ctx.response()
                                    .setStatusCode(500)
                                    .putHeader("Content-Type", "application/json")
                                    .end(Json.encode(new ErrorResponse("500", "Internal server error")));
                        }
                );
    }

    /**
     * Fetch holdings from PostgreSQL database
     * Endpoint: GET /v1/holding/db
     */
    public void fetchAllHoldingsFromDb(RoutingContext ctx) {
        MdcTraceCorrelation.updateMdc();

        String userId = ctx.request().getHeader(AUTH_HEADER_USER_ID);
        String tradingType = ctx.request().getParam("trading_type");

        VertxTracing.addAttributes(Map.of(
                "user.id", userId != null ? userId : "unknown",
                "request.trading_type", tradingType != null ? tradingType : "all",
                "data.source", "postgresql"
        ));

        if (userId == null || userId.isEmpty()) {
            log.warn("Request rejected: missing userId header");
            ctx.response()
                    .setStatusCode(400)
                    .putHeader("Content-Type", "application/json")
                    .end(Json.encode(new ErrorResponse("400", "userId cannot be null")));
            return;
        }

        log.info("Received fetchAllHoldingsFromDb request for userId: {}, tradingType: {}", userId, tradingType);

        List<String> tradingTypes = holdingService.parseTradingTypes(tradingType);

        // Fetch from PostgreSQL and then enrich with GraphQL
        holdingService.fetchAllHoldingsFromDb(userId, tradingTypes)
                .flatMap(response -> {
                    if (response != null && response.getHoldings() != null && !response.getHoldings().isEmpty()) {
                        return graphQLService.enrichHoldingsWithScripDetails(response.getHoldings())
                                .map(enrichedHoldings -> {
                                    response.setHoldings(enrichedHoldings);
                                    VertxTracing.addEvent("holdings.enriched.from.db",
                                            Map.of("count", enrichedHoldings.size()));
                                    log.info("Successfully fetched and enriched {} holdings from DB for user {}",
                                            enrichedHoldings.size(), userId);
                                    return response;
                                })
                                .onErrorResumeNext(error -> {
                                    log.warn("Failed to enrich DB holdings, returning original", error);
                                    return io.reactivex.rxjava3.core.Single.just(response);
                                });
                    }
                    return io.reactivex.rxjava3.core.Single.just(response);
                })
                .subscribe(
                        response -> {
                            MdcTraceCorrelation.updateMdc();
                            ctx.response()
                                    .setStatusCode(200)
                                    .putHeader("Content-Type", "application/json")
                                    .end(Json.encode(response));
                        },
                        error -> {
                            MdcTraceCorrelation.updateMdc();
                            log.error("Error fetching holdings from DB for userId: {}", userId, error);
                            VertxTracing.recordException(error);
                            ctx.response()
                                    .setStatusCode(500)
                                    .putHeader("Content-Type", "application/json")
                                    .end(Json.encode(new ErrorResponse("500",
                                            "Database error: " + error.getMessage())));
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
