package com.example.holding.services;

import com.example.holding.dto.HoldingData;
import io.reactivex.rxjava3.core.Single;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.stream.Collectors;

public class GraphQLService {
    private static final Logger log = LoggerFactory.getLogger(GraphQLService.class);

    public Single<List<HoldingData>> enrichHoldingsWithScripDetails(List<HoldingData> holdings) {
        log.info("Enriching {} holdings with scrip details", holdings.size());

        return Single.fromCallable(() -> {
            return holdings.stream()
                    .map(h -> new HoldingData(
                            h.getSymbol(),
                            h.getTradingType(),
                            h.getQuantity(),
                            h.getAvgPrice(),
                            h.getCurrentPrice(),
                            h.getPnl()
                    ))
                    .collect(Collectors.toList());
        });
    }
}
