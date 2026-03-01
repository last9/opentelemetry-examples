package com.example.holding.services;

import com.example.holding.dto.HoldingData;
import io.otel.rxjava.vertx.operators.Traced;
import io.reactivex.rxjava3.core.Single;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

public class GraphQLService {
    private static final Logger log = LoggerFactory.getLogger(GraphQLService.class);

    public Single<List<HoldingData>> enrichHoldingsWithScripDetails(List<HoldingData> holdings) {

        return Traced.call(
                "GraphQLService.enrichHoldings",
                Map.of("holdings.count", holdings.size()),
                () -> {
                    log.info("Enriching {} holdings with scrip details", holdings.size());

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
