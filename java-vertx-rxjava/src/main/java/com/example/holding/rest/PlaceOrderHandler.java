package com.example.holding.rest;

import com.example.holding.dto.PlaceOrderRequest;
import com.example.holding.services.OrderService;
import io.vertx.core.json.Json;
import io.vertx.rxjava3.ext.web.RoutingContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * REST endpoint for placing orders
 */
public class PlaceOrderHandler {
    private static final Logger log = LoggerFactory.getLogger(PlaceOrderHandler.class);
    private static final String AUTH_HEADER_USER_ID = "X-User-Id";

    private final OrderService orderService;

    public PlaceOrderHandler(OrderService orderService) {
        this.orderService = orderService;
    }

    /**
     * Places a new order for the specified user
     *
     * @param ctx the routing context
     */
    public void placeOrder(RoutingContext ctx) {
        String userId = ctx.request().getHeader(AUTH_HEADER_USER_ID);

        if (userId == null || userId.isEmpty()) {
            ctx.response()
                    .setStatusCode(400)
                    .putHeader("Content-Type", "application/json")
                    .end(Json.encode(new ErrorResponse("400", "userId cannot be null")));
            return;
        }

        PlaceOrderRequest request;
        try {
            request = ctx.body().asPojo(PlaceOrderRequest.class);
        } catch (Exception e) {
            log.error("Failed to parse place order request", e);
            ctx.response()
                    .setStatusCode(400)
                    .putHeader("Content-Type", "application/json")
                    .end(Json.encode(new ErrorResponse("400", "Invalid request body")));
            return;
        }

        log.info("Placing order {} for userId: {}", request.getSymbol(), userId);

        orderService.placeOrder(request, userId)
                .subscribe(
                        response -> {
                            int statusCode = "PLACED".equals(response.getStatus()) ? 200 : 500;
                            ctx.response()
                                    .setStatusCode(statusCode)
                                    .putHeader("Content-Type", "application/json")
                                    .end(Json.encode(response));
                        },
                        error -> {
                            log.error("Error placing order for userId: {}", userId, error);
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
