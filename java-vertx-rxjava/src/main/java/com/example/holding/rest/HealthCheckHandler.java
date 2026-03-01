package com.example.holding.rest;

import io.vertx.core.json.JsonObject;
import io.vertx.rxjava3.ext.web.RoutingContext;

public class HealthCheckHandler {

    public void health(RoutingContext ctx) {
        ctx.response()
                .setStatusCode(200)
                .putHeader("Content-Type", "application/json")
                .end(new JsonObject()
                        .put("status", "UP")
                        .put("service", "holding-service")
                        .encode());
    }
}
