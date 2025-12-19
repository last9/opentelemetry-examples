package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

// User represents a user model
type User struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
}

// Order represents an order model
type Order struct {
	ID        int       `json:"id"`
	UserID    int       `json:"user_id"`
	Product   string    `json:"product"`
	Amount    float64   `json:"amount"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

var db *sql.DB

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Initialize SQLite database
	initDB()

	// Setup routes - eBPF will auto-instrument all these!
	http.HandleFunc("/", homeHandler)
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/api/users", usersHandler)
	http.HandleFunc("/api/users/", userByIDHandler)
	http.HandleFunc("/api/orders", ordersHandler)
	http.HandleFunc("/api/orders/create", createOrderHandler)
	http.HandleFunc("/api/external", externalCallHandler)
	http.HandleFunc("/api/chain", chainedCallHandler)
	http.HandleFunc("/api/slow", slowHandler)
	http.HandleFunc("/api/error", errorHandler)

	log.Printf("Server starting on port %s", port)
	log.Printf("eBPF will auto-instrument: net/http, database/sql")
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func initDB() {
	var err error
	db, err = sql.Open("sqlite3", ":memory:")
	if err != nil {
		log.Fatalf("Failed to open database: %v", err)
	}

	// Create tables
	_, err = db.Exec(`
		CREATE TABLE users (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL,
			email TEXT UNIQUE NOT NULL,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP
		);

		CREATE TABLE orders (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id INTEGER NOT NULL,
			product TEXT NOT NULL,
			amount REAL NOT NULL,
			status TEXT DEFAULT 'pending',
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			FOREIGN KEY (user_id) REFERENCES users(id)
		);
	`)
	if err != nil {
		log.Fatalf("Failed to create tables: %v", err)
	}

	// Seed data
	seedData()
	log.Println("SQLite in-memory database initialized")
}

func seedData() {
	// Insert users
	users := []struct {
		name  string
		email string
	}{
		{"Alice Johnson", "alice@example.com"},
		{"Bob Smith", "bob@example.com"},
		{"Charlie Brown", "charlie@example.com"},
		{"Diana Prince", "diana@example.com"},
	}

	for _, u := range users {
		db.Exec("INSERT INTO users (name, email) VALUES (?, ?)", u.name, u.email)
	}

	// Insert orders
	orders := []struct {
		userID  int
		product string
		amount  float64
		status  string
	}{
		{1, "Laptop", 1299.99, "completed"},
		{1, "Mouse", 49.99, "completed"},
		{2, "Keyboard", 149.99, "pending"},
		{3, "Monitor", 399.99, "shipped"},
		{4, "Headphones", 199.99, "pending"},
	}

	for _, o := range orders {
		db.Exec("INSERT INTO orders (user_id, product, amount, status) VALUES (?, ?, ?, ?)",
			o.userID, o.product, o.amount, o.status)
	}
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	response := map[string]interface{}{
		"message": "Go eBPF Auto-Instrumentation Demo",
		"endpoints": map[string]string{
			"GET  /health":            "Health check",
			"GET  /api/users":         "List all users (DB query)",
			"GET  /api/users/{id}":    "Get user by ID (DB query)",
			"GET  /api/orders":        "List all orders (DB query with JOIN)",
			"POST /api/orders/create": "Create order (DB insert)",
			"GET  /api/external":      "External HTTP call",
			"GET  /api/chain":         "Chained service calls",
			"GET  /api/slow":          "Slow endpoint (500ms)",
			"GET  /api/error":         "Error endpoint (500)",
		},
		"instrumentation": "eBPF (zero-code)",
		"traces_include":  []string{"HTTP requests", "SQL queries", "External calls"},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	// Check database connection
	err := db.Ping()
	dbStatus := "healthy"
	if err != nil {
		dbStatus = "unhealthy"
	}

	response := map[string]interface{}{
		"status":   "healthy",
		"database": dbStatus,
		"time":     time.Now().UTC().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func usersHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// eBPF will trace this SQL query
	rows, err := db.Query("SELECT id, name, email, created_at FROM users ORDER BY id")
	if err != nil {
		http.Error(w, fmt.Sprintf("Database error: %v", err), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Name, &u.Email, &u.CreatedAt); err != nil {
			continue
		}
		users = append(users, u)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(users)
}

func userByIDHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	id := r.URL.Path[len("/api/users/"):]
	if id == "" {
		http.Error(w, "User ID required", http.StatusBadRequest)
		return
	}

	// eBPF will trace this query with parameter
	var user User
	err := db.QueryRow("SELECT id, name, email, created_at FROM users WHERE id = ?", id).
		Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)

	if err == sql.ErrNoRows {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	} else if err != nil {
		http.Error(w, fmt.Sprintf("Database error: %v", err), http.StatusInternalServerError)
		return
	}

	// Also fetch user's orders - another traced query
	rows, err := db.Query("SELECT id, product, amount, status, created_at FROM orders WHERE user_id = ?", id)
	if err == nil {
		defer rows.Close()
		var orders []Order
		for rows.Next() {
			var o Order
			if err := rows.Scan(&o.ID, &o.Product, &o.Amount, &o.Status, &o.CreatedAt); err != nil {
				continue
			}
			o.UserID = user.ID
			orders = append(orders, o)
		}

		response := map[string]interface{}{
			"user":   user,
			"orders": orders,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

func ordersHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// eBPF will trace this JOIN query
	rows, err := db.Query(`
		SELECT o.id, o.user_id, u.name, o.product, o.amount, o.status, o.created_at
		FROM orders o
		JOIN users u ON o.user_id = u.id
		ORDER BY o.created_at DESC
	`)
	if err != nil {
		http.Error(w, fmt.Sprintf("Database error: %v", err), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type OrderWithUser struct {
		Order
		UserName string `json:"user_name"`
	}

	var orders []OrderWithUser
	for rows.Next() {
		var o OrderWithUser
		if err := rows.Scan(&o.ID, &o.UserID, &o.UserName, &o.Product, &o.Amount, &o.Status, &o.CreatedAt); err != nil {
			continue
		}
		orders = append(orders, o)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(orders)
}

func createOrderHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var input struct {
		UserID  int     `json:"user_id"`
		Product string  `json:"product"`
		Amount  float64 `json:"amount"`
	}

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// Verify user exists - traced query
	var userID int
	err := db.QueryRow("SELECT id FROM users WHERE id = ?", input.UserID).Scan(&userID)
	if err == sql.ErrNoRows {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}

	// Insert order - traced query
	result, err := db.Exec(
		"INSERT INTO orders (user_id, product, amount, status) VALUES (?, ?, ?, 'pending')",
		input.UserID, input.Product, input.Amount,
	)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to create order: %v", err), http.StatusInternalServerError)
		return
	}

	orderID, _ := result.LastInsertId()

	response := map[string]interface{}{
		"message":  "Order created successfully",
		"order_id": orderID,
		"status":   "pending",
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(response)
}

func externalCallHandler(w http.ResponseWriter, r *http.Request) {
	// Make external HTTP call - eBPF traces outgoing HTTP
	client := &http.Client{Timeout: 5 * time.Second}

	// Call a public API
	resp, err := client.Get("https://httpbin.org/json")
	if err != nil {
		http.Error(w, fmt.Sprintf("External call failed: %v", err), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	response := map[string]interface{}{
		"message":          "External API call completed",
		"external_url":     "https://httpbin.org/json",
		"external_status":  resp.StatusCode,
		"external_response": json.RawMessage(body),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func chainedCallHandler(w http.ResponseWriter, r *http.Request) {
	start := time.Now()

	// Step 1: Query database
	var userCount int
	db.QueryRow("SELECT COUNT(*) FROM users").Scan(&userCount)

	// Step 2: Query orders
	var orderCount int
	db.QueryRow("SELECT COUNT(*) FROM orders").Scan(&orderCount)

	// Step 3: Calculate totals
	var totalAmount float64
	db.QueryRow("SELECT COALESCE(SUM(amount), 0) FROM orders WHERE status = 'completed'").Scan(&totalAmount)

	// Step 4: External call for exchange rate (simulated)
	client := &http.Client{Timeout: 3 * time.Second}
	resp, _ := client.Get("https://httpbin.org/delay/1")
	if resp != nil {
		resp.Body.Close()
	}

	response := map[string]interface{}{
		"message": "Chained operations completed",
		"stats": map[string]interface{}{
			"user_count":     userCount,
			"order_count":    orderCount,
			"completed_total": totalAmount,
		},
		"duration_ms": time.Since(start).Milliseconds(),
		"operations":  []string{"DB: count users", "DB: count orders", "DB: sum amounts", "HTTP: external API"},
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func slowHandler(w http.ResponseWriter, r *http.Request) {
	// Simulate slow processing
	time.Sleep(500 * time.Millisecond)

	// Also do a slow query
	var count int
	db.QueryRow("SELECT COUNT(*) FROM orders WHERE status = 'pending'").Scan(&count)

	response := map[string]interface{}{
		"message":        "Slow operation completed",
		"duration":       "500ms",
		"pending_orders": count,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func errorHandler(w http.ResponseWriter, r *http.Request) {
	// Simulate an error scenario
	// Try to query non-existent table
	_, err := db.Query("SELECT * FROM nonexistent_table")

	response := map[string]interface{}{
		"error":   "Internal server error",
		"details": err.Error(),
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusInternalServerError)
	json.NewEncoder(w).Encode(response)
}
