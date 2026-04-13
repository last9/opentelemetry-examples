package com.example.bodycapture;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

@RestController
@RequestMapping("/api")
public class ApiController {

    private final Map<Integer, Map<String, Object>> users = new ConcurrentHashMap<>();
    private final AtomicInteger idSeq = new AtomicInteger(1);

    @PostMapping("/users")
    public ResponseEntity<Map<String, Object>> createUser(@RequestBody Map<String, Object> body) {
        int id = idSeq.getAndIncrement();
        body.put("id", id);
        users.put(id, body);
        return ResponseEntity.status(201).body(body);
    }

    @GetMapping("/users/{id}")
    public ResponseEntity<Map<String, Object>> getUser(@PathVariable int id) {
        Map<String, Object> user = users.get(id);
        if (user == null) {
            return ResponseEntity.status(404).body(Map.of("error", "user not found", "id", id));
        }
        return ResponseEntity.ok(user);
    }

    @PostMapping("/echo")
    public ResponseEntity<Map<String, Object>> echo(@RequestBody Map<String, Object> body) {
        return ResponseEntity.ok(body);
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> health() {
        return ResponseEntity.ok(Map.of("status", "ok"));
    }
}
