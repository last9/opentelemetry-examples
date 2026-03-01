package com.example.holding.services;

import com.example.holding.dto.PlaceOrderRequest;
import com.example.holding.dto.PlaceOrderResponse;
import io.otel.rxjava.vertx.operators.Traced;
import io.reactivex.rxjava3.core.Single;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Map;
import java.util.UUID;

/**
 * Order service with OpenTelemetry tracing.
 *
 * Changes from original:
 * 1. Use Traced.call() to create child spans
 * 2. Add order-specific attributes to spans
 */
public class OrderService {
    private static final Logger log = LoggerFactory.getLogger(OrderService.class);

    public Single<PlaceOrderResponse> placeOrder(PlaceOrderRequest request, String userId) {

        return Traced.call(
                "OrderService.placeOrder",
                Map.of(
                        "user.id", userId,
                        "order.symbol", request.getSymbol(),
                        "order.quantity", request.getQuantity(),
                        "order.type", request.getOrderType() != null ? request.getOrderType() : "MARKET"
                ),
                () -> {
                    log.info("Placing order for userId: {}, symbol: {}, quantity: {}",
                            userId, request.getSymbol(), request.getQuantity());

                    // Simulate order placement
                    String orderId = UUID.randomUUID().toString();

                    log.info("Order {} placed successfully for user {}", orderId, userId);

                    return new PlaceOrderResponse(orderId, "PLACED", "Order placed successfully");
                })
                .onErrorReturn(error -> {
                    log.error("Error placing order for user {}: {}", userId, error.getMessage());
                    return new PlaceOrderResponse(null, "FAILED", "Failed to place order: " + error.getMessage());
                });
    }
}
