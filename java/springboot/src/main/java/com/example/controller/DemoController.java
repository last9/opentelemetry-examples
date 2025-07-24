package com.example.controller;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;
import java.util.Random;

@RestController
@RequestMapping("/api")
public class DemoController {
    
    private static final Logger logger = LoggerFactory.getLogger(DemoController.class);
    
    @Autowired
    private Tracer tracer;
    
    private final Random random = new Random();

    @GetMapping("/hello")
    public ResponseEntity<Map<String, String>> hello() {
        logger.info("Hello endpoint called");
        Span span = tracer.spanBuilder("hello-operation").startSpan();
        try {
            // Simulate some work
            Thread.sleep(random.nextInt(100) + 50);
            
            Map<String, String> response = new HashMap<>();
            response.put("message", "Hello, World!");
            response.put("timestamp", String.valueOf(System.currentTimeMillis()));
            
            span.setAttribute("response.message", "Hello, World!");
            return ResponseEntity.ok(response);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return ResponseEntity.internalServerError().build();
        } finally {
            span.end();
        }
    }

    @GetMapping("/users/{id}")
    public ResponseEntity<Map<String, Object>> getUser(@PathVariable Long id) {
        logger.info("Get user endpoint called with id: {}", id);
        Span span = tracer.spanBuilder("get-user-operation").startSpan();
        try {
            span.setAttribute("user.id", id);
            
            // Simulate some work
            Thread.sleep(random.nextInt(200) + 100);
            
            Map<String, Object> user = new HashMap<>();
            user.put("id", id);
            user.put("name", "User " + id);
            user.put("email", "user" + id + "@example.com");
            user.put("timestamp", System.currentTimeMillis());
            
            span.setAttribute("user.name", "User " + id);
            return ResponseEntity.ok(user);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return ResponseEntity.internalServerError().build();
        } finally {
            span.end();
        }
    }

    @PostMapping("/users")
    public ResponseEntity<Map<String, Object>> createUser(@RequestBody Map<String, String> userData) {
        logger.info("Create user endpoint called with data: {}", userData);
        Span span = tracer.spanBuilder("create-user-operation").startSpan();
        try {
            span.setAttribute("user.name", userData.get("name"));
            
            // Simulate some work
            Thread.sleep(random.nextInt(300) + 150);
            
            Map<String, Object> response = new HashMap<>();
            response.put("id", random.nextLong(1000));
            response.put("name", userData.get("name"));
            response.put("email", userData.get("email"));
            response.put("status", "created");
            response.put("timestamp", System.currentTimeMillis());
            
            span.setAttribute("user.id", ((Number)response.get("id")).longValue());
            return ResponseEntity.ok(response);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return ResponseEntity.internalServerError().build();
        } finally {
            span.end();
        }
    }

    @GetMapping("/products")
    public ResponseEntity<Map<String, Object>> getProducts(@RequestParam(defaultValue = "10") int limit) {
        logger.info("Get products endpoint called with limit: {}", limit);
        Span span = tracer.spanBuilder("get-products-operation").startSpan();
        try {
            span.setAttribute("products.limit", limit);
            
            // Simulate some work
            Thread.sleep(random.nextInt(250) + 100);
            
            Map<String, Object> response = new HashMap<>();
            response.put("products", java.util.Arrays.asList(
                Map.of("id", 1, "name", "Product 1", "price", 99.99),
                Map.of("id", 2, "name", "Product 2", "price", 149.99),
                Map.of("id", 3, "name", "Product 3", "price", 199.99)
            ));
            response.put("total", 3);
            response.put("limit", limit);
            response.put("timestamp", System.currentTimeMillis());
            
            return ResponseEntity.ok(response);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return ResponseEntity.internalServerError().build();
        } finally {
            span.end();
        }
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        logger.info("Health check endpoint called");
        Map<String, String> response = new HashMap<>();
        response.put("status", "UP");
        response.put("timestamp", String.valueOf(System.currentTimeMillis()));
        return ResponseEntity.ok(response);
    }

    @GetMapping("/error-demo")
    public ResponseEntity<Map<String, String>> errorDemo() {
        logger.error("Error demo endpoint called - generating error");
        Span span = tracer.spanBuilder("error-demo-operation").startSpan();
        try {
            span.setAttribute("error.type", "demo-error");
            throw new RuntimeException("This is a demo error for testing error handling");
        } finally {
            span.end();
        }
    }
} 