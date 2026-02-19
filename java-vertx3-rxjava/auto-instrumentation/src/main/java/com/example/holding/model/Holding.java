package com.example.holding.model;

import io.vertx.core.json.JsonObject;

/**
 * Holding entity representing a user's stock holding.
 */
public class Holding {

    private final Long id;
    private final String userId;
    private final String symbol;
    private final Integer quantity;

    public Holding(Long id, String userId, String symbol, Integer quantity) {
        this.id = id;
        this.userId = userId;
        this.symbol = symbol;
        this.quantity = quantity;
    }

    public static Holding fromJson(JsonObject json) {
        return new Holding(
                json.getLong("id"),
                json.getString("user_id"),
                json.getString("symbol"),
                json.getInteger("quantity")
        );
    }

    public Long getId() {
        return id;
    }

    public String getUserId() {
        return userId;
    }

    public String getSymbol() {
        return symbol;
    }

    public Integer getQuantity() {
        return quantity;
    }

    public JsonObject toJson() {
        JsonObject json = new JsonObject()
                .put("userId", userId)
                .put("symbol", symbol)
                .put("quantity", quantity);
        if (id != null) {
            json.put("id", id);
        }
        return json;
    }
}
