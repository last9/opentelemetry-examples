# Understanding `Traced.call()` - When and Why to Use It

## The Problem

With just the SDK initialization, you only get **one span per HTTP request** (the parent HTTP span created by Vert.x). Your trace looks like:

```
GET /v1/holding    ← Single span, no visibility into what happened inside
```

You have **no visibility** into:
- Which service methods were called
- How long each method took
- Where errors occurred
- Database query performance

---

## What `Traced.call()` Does

It creates **child spans** that show the internal flow:

```
GET /v1/holding                              ← Parent (automatic from Vert.x)
├── HoldingService.fetchHoldings             ← Child (you add this)
│   └── attributes: user.id=123
├── PostgresRepository.query                 ← Child (you add this)
│   └── attributes: db.system=postgresql
└── GraphQLService.enrich                    ← Child (you add this)
```

---

## Do You Need It Everywhere? **NO**

Add `Traced.call()` only to **important operations** you want visibility into:

| Add Tracing | Skip Tracing |
|-------------|--------------|
| Database queries | Simple getters/setters |
| External API calls | Utility methods |
| Service layer methods | Pure transformations |
| Expensive computations | Validation logic |
| Async operations you want to track | Internal helper methods |

---

## Before vs After

**Before (no child spans):**
```java
public Single<Holdings> fetchHoldings(String userId) {
    return repository.findByUserId(userId);  // No visibility
}
```

**After (with tracing):**
```java
public Single<Holdings> fetchHoldings(String userId) {
    return Traced.call(
        "HoldingService.fetchHoldings",      // Span name
        Map.of("user.id", userId),           // Attributes (optional)
        () -> repository.findByUserId(userId)
    );
}
```

---

## When to Use Which Method

```java
// Traced.call() - for sync operations returning a value
Traced.call("spanName", () -> syncOperation())

// Traced.single() - for operations that already return Single<T>
Traced.single("spanName", () -> asyncOperation())  // asyncOperation returns Single<T>

// Traced.completable() - for void async operations
Traced.completable("spanName", () -> fireAndForget())

// Traced.run() - for sync void operations
Traced.run("spanName", () -> sideEffect())
```

---

## Minimal Changes Approach

For a typical app, you might only add tracing to **5-10 key methods**:

1. **Service layer entry points** (e.g., `HoldingService.fetchHoldings`)
2. **Database repository methods** (e.g., `PostgresRepository.findByUser`)
3. **External API calls** (e.g., `GraphQLService.enrich`)

You do **NOT** need to wrap every single method - just the ones where you want observability.

---

## Examples

### Database Query
```java
public Single<List<User>> findAll() {
    return Traced.single(
        "UserRepository.findAll",
        Map.of("db.system", "postgresql", "db.operation", "SELECT"),
        () -> pgPool.query("SELECT * FROM users").rxExecute()
                .map(this::mapRows)
    );
}
```

### External API Call
```java
public Single<EnrichedData> enrichWithExternalApi(String id) {
    return Traced.single(
        "ExternalApi.enrich",
        Map.of("api.endpoint", "/enrich", "record.id", id),
        () -> webClient.get("/api/enrich/" + id).rxSend()
                .map(this::parseResponse)
    );
}
```

### Service Method with Multiple Operations
```java
public Single<OrderResult> placeOrder(OrderRequest request) {
    return Traced.single(
        "OrderService.placeOrder",
        Map.of(
            "order.symbol", request.getSymbol(),
            "order.quantity", request.getQuantity()
        ),
        () -> validateOrder(request)
                .flatMap(valid -> saveToDatabase(request))
                .flatMap(saved -> notifyExchange(saved))
    );
}
```

---

## Summary

| Question | Answer |
|----------|--------|
| Is it required? | No, but highly recommended for key operations |
| Every method? | No, only important ones (DB, APIs, services) |
| What if I skip it? | You only see HTTP spans, no internal details |
| Performance impact? | Minimal (~microseconds per span) |

---

## API Reference

### `Traced.call()`
```java
// Basic usage
Traced.call("spanName", () -> operation())

// With attributes
Traced.call("spanName", Map.of("key", "value"), () -> operation())

// With attributes and span kind
Traced.call("spanName", Map.of("key", "value"), SpanKind.CLIENT, () -> operation())
```

### `Traced.single()`
```java
// For operations returning Single<T>
Traced.single("spanName", () -> singleOperation())

// With attributes
Traced.single("spanName", Map.of("key", "value"), () -> singleOperation())
```

### `Traced.completable()`
```java
// For operations returning Completable
Traced.completable("spanName", () -> completableOperation())
```

### `Traced.run()`
```java
// For void sync operations (returns Completable)
Traced.run("spanName", () -> voidOperation())
```
