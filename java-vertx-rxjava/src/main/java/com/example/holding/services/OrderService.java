package com.example.holding.services;

import com.example.holding.dto.PlaceOrderRequest;
import com.example.holding.dto.PlaceOrderResponse;
import io.reactivex.rxjava3.core.Single;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.UUID;

public class OrderService {
    private static final Logger log = LoggerFactory.getLogger(OrderService.class);

    public Single<PlaceOrderResponse> placeOrder(PlaceOrderRequest request, String userId) {
        log.info("Placing order for userId: {}, symbol: {}, quantity: {}",
                userId, request.getSymbol(), request.getQuantity());

        return Single.fromCallable(() -> {
            String orderId = UUID.randomUUID().toString();
            log.info("Order {} placed successfully for user {}", orderId, userId);
            return new PlaceOrderResponse(orderId, "PLACED", "Order placed successfully");
        }).doOnError(error ->
                log.error("Error placing order for user {}: {}", userId, error.getMessage())
        ).onErrorReturn(error ->
                new PlaceOrderResponse(null, "FAILED", "Failed to place order: " + error.getMessage())
        );
    }
}
