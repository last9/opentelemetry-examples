package com.example.holding.services;

import com.example.holding.dto.HoldingData;
import io.otel.rxjava.vertx.operators.Traced;
import io.reactivex.rxjava3.core.Single;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * GraphQL service for enriching holdings with scrip details.
 *
 * Changes from original:
 * 1. Use Traced.call() to create child spans
 * 2. Logs automatically include trace_id/span_id via MDC
 */
public class GraphQLService {
    private static final Logger log = LoggerFactory.getLogger(GraphQLService.class);

    public Single<List<HoldingData>> enrichHoldingsWithScripDetails(List<HoldingData> holdings) {

        // This creates a child span "GraphQLService.enrichHoldings"
        // When called from the handler's flatMap, it will be a child of the HTTP span
        return Traced.call(
                "GraphQLService.enrichHoldings",
                Map.of("holdings.count", holdings.size()),
                () -> {
                    // This log will have the same trace_id as the parent request
                    log.info("Enriching {} holdings with scrip details", holdings.size());

                    // Simulate enrichment (in real app, this would call external GraphQL API)
                    List<HoldingData> enriched = holdings.stream()
                            .map(h -> new HoldingData(
                                    h.getSymbol(),
                                    h.getTradingType(),
                                    h.getQuantity(),
                                    h.getAvgPrice(),
                                    h.getCurrentPrice(),
                                    h.getPnl()
                            ))
                            .collect(Collectors.toList());

                    log.info("Successfully enriched {} holdings", enriched.size());

                    return enriched;
                });
    }
}
