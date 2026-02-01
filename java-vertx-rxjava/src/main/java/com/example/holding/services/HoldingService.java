package com.example.holding.services;

import com.example.holding.dto.GetAllHoldingsResponse;
import com.example.holding.dto.HoldingData;
import io.reactivex.rxjava3.core.Single;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

public class HoldingService {
    private static final Logger log = LoggerFactory.getLogger(HoldingService.class);

    public Single<GetAllHoldingsResponse> fetchAllHoldingsByUserIdAndTradingTypes(
            String userId, List<String> tradingTypes, String symbol) {

        log.info("Fetching holdings for userId: {}, tradingTypes: {}, symbol: {}",
                userId, tradingTypes, symbol);

        return Single.fromCallable(() -> {
            List<HoldingData> holdings = getMockHoldings(tradingTypes, symbol);
            return new GetAllHoldingsResponse(userId, holdings, holdings.size(), "Successfully fetched holdings");
        });
    }

    public List<String> parseTradingTypes(String tradingType) {
        if (tradingType == null || tradingType.isEmpty()) {
            return Arrays.asList("EQUITY", "F&O");
        }
        return Arrays.asList(tradingType.split(","));
    }

    private List<HoldingData> getMockHoldings(List<String> tradingTypes, String symbol) {
        List<HoldingData> allHoldings = Arrays.asList(
                new HoldingData("RELIANCE", "EQUITY", 100, 2450.50, 2520.75, 7025.0),
                new HoldingData("TCS", "EQUITY", 50, 3800.00, 3750.25, -2487.5),
                new HoldingData("NIFTY24FEB", "F&O", 25, 21500.00, 21750.00, 6250.0)
        );

        return allHoldings.stream()
                .filter(h -> tradingTypes.contains(h.getTradingType()))
                .filter(h -> symbol == null || symbol.isEmpty() || h.getSymbol().contains(symbol))
                .collect(Collectors.toList());
    }
}
