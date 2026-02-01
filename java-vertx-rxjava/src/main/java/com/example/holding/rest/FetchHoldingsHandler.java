package com.example.holding.rest;

import com.example.holding.dto.GetAllHoldingsResponse;
import com.example.holding.services.GraphQLService;
import com.example.holding.services.HoldingService;
import io.vertx.core.json.Json;
import io.vertx.rxjava3.ext.web.RoutingContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;

/**
 * REST endpoint for fetching holdings by user ID and trading type with cursor-based pagination
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
     * Fetches holdings for a user based on trading type(s)
     * Supports multiple trading types (comma-separated or array format)
     *
     * @param ctx the routing context
     */
    public void fetchAllHoldings(RoutingContext ctx) {
        String userId = ctx.request().getHeader(AUTH_HEADER_USER_ID);
        String tradingType = ctx.request().getParam("trading_type");
        String symbol = ctx.request().getParam("symbol");

        if (userId == null || userId.isEmpty()) {
            ctx.response()
                    .setStatusCode(400)
                    .putHeader("Content-Type", "application/json")
                    .end(Json.encode(new ErrorResponse("400", "userId cannot be null")));
            return;
        }

        log.info("Received fetchAllHoldings request for userId: {}, tradingType: {}, symbol: {}",
                userId, tradingType, symbol);

        // Parse trading types (comma-separated or array format)
        List<String> tradingTypes = holdingService.parseTradingTypes(tradingType);

        holdingService.fetchAllHoldingsByUserIdAndTradingTypes(userId, tradingTypes, symbol)
                .flatMap(response -> {
                    // Enrich holdings with scrip details from GraphQL service
                    if (response != null && response.getHoldings() != null && !response.getHoldings().isEmpty()) {
                        return graphQLService.enrichHoldingsWithScripDetails(response.getHoldings())
                                .map(enrichedHoldings -> {
                                    response.setHoldings(enrichedHoldings);
                                    int holdingsCount = enrichedHoldings.size();
                                    log.info("Successfully processed fetch all holdings request for userId: {}, tradingTypes: {}, symbol: {}, holdingsCount: {}",
                                            userId, tradingTypes, symbol, holdingsCount);
                                    return response;
                                })
                                .onErrorResumeNext(error -> {
                                    log.warn("Failed to enrich holdings with scrip details, returning original response", error);
                                    int holdingsCount = response.getHoldings().size();
                                    log.info("Successfully processed fetch all holdings request for userId: {}, tradingTypes: {}, symbol: {}, holdingsCount: {}",
                                            userId, tradingTypes, symbol, holdingsCount);
                                    return io.reactivex.rxjava3.core.Single.just(response);
                                });
                    }
                    return io.reactivex.rxjava3.core.Single.just(response);
                })
                .subscribe(
                        response -> {
                            ctx.response()
                                    .setStatusCode(200)
                                    .putHeader("Content-Type", "application/json")
                                    .end(Json.encode(response));
                        },
                        error -> {
                            log.error("Error fetching holdings for userId: {}", userId, error);
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
