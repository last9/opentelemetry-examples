// Package main demonstrates how to instrument a Go net/http server
// with the Last9 Go Agent for automatic tracing and metrics.
//
// This example shows multiple patterns for instrumenting net/http:
// 1. Using NewServeMux() - recommended for new applications
// 2. Using WrapHandler() - for existing applications
// 3. Using Handler() - for individual handler instrumentation
// 4. Database integration with automatic query tracing
// 5. HTTP client instrumentation with trace propagation
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/last9/go-agent"
	"github.com/last9/go-agent/integrations/database"
	httpagent "github.com/last9/go-agent/integrations/http"
	"github.com/last9/go-agent/instrumentation/nethttp"

	_ "github.com/mattn/go-sqlite3" // SQLite driver
)

// User represents a simple user model
type User struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
}

// Global database connection
var db *sql.DB

func main() {
	// Start the Last9 agent - this sets up OpenTelemetry tracing and metrics
	// Configuration is read from environment variables:
	//   OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_EXPORTER_OTLP_HEADERS, OTEL_SERVICE_NAME
	if err := agent.Start(); err != nil {
		log.Fatalf("Failed to start agent: %v", err)
	}
	defer agent.Shutdown()

	// Initialize database with instrumentation
	var err error
	db, err = database.Open(database.Config{
		DriverName:   "sqlite3",
		DSN:          "file:users.db?cache=shared&mode=rwc",
		DatabaseName: "users",
	})
	if err != nil {
		log.Fatalf("Failed to open database: %v", err)
	}
	defer db.Close()

	// Create users table
	if err := initDB(); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	// Option 1: Use instrumented ServeMux (RECOMMENDED for new applications)
	// Each handler automatically gets traced with the route pattern as span name
	mux := nethttp.NewServeMux()

	// Register handlers - each is automatically instrumented
	mux.HandleFunc("/", homeHandler)
	mux.HandleFunc("/health", healthHandler)

	// User CRUD with database
	mux.HandleFunc("GET /users", listUsersHandler)
	mux.HandleFunc("POST /users", createUserHandler)
	mux.HandleFunc("GET /users/{id}", getUserHandler)
	mux.HandleFunc("PUT /users/{id}", updateUserHandler)
	mux.HandleFunc("DELETE /users/{id}", deleteUserHandler)

	// External API call example
	mux.HandleFunc("/joke", jokeHandler)

	log.Println("Starting server on http://localhost:8080")
	log.Println("")
	log.Println("Try these endpoints:")
	log.Println("  GET    http://localhost:8080/")
	log.Println("  GET    http://localhost:8080/health")
	log.Println("  GET    http://localhost:8080/users          - List all users (DB query)")
	log.Println("  POST   http://localhost:8080/users          - Create user (DB insert)")
	log.Println("  GET    http://localhost:8080/users/1        - Get user by ID (DB query)")
	log.Println("  PUT    http://localhost:8080/users/1        - Update user (DB update)")
	log.Println("  DELETE http://localhost:8080/users/1        - Delete user (DB delete)")
	log.Println("  GET    http://localhost:8080/joke           - External API call")
	log.Println("")

	// Start the server
	if err := http.ListenAndServe(":8080", mux); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

// initDB creates the users table and seeds initial data
func initDB() error {
	// Create table
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS users (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL,
			email TEXT NOT NULL UNIQUE,
			created_at DATETIME DEFAULT CURRENT_TIMESTAMP
		)
	`)
	if err != nil {
		return fmt.Errorf("failed to create table: %w", err)
	}

	// Check if we have any users
	var count int
	err = db.QueryRow("SELECT COUNT(*) FROM users").Scan(&count)
	if err != nil {
		return fmt.Errorf("failed to count users: %w", err)
	}

	// Seed initial users if empty
	if count == 0 {
		_, err = db.Exec(`
			INSERT INTO users (name, email) VALUES
			('Alice', 'alice@example.com'),
			('Bob', 'bob@example.com')
		`)
		if err != nil {
			return fmt.Errorf("failed to seed users: %w", err)
		}
		log.Println("Database initialized with sample users")
	}

	return nil
}

// homeHandler returns a welcome message
func homeHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Welcome to the net/http + database instrumentation example!",
		"docs":    "Try GET /users, POST /users, GET /users/1, GET /joke",
	})
}

// healthHandler returns health status
func healthHandler(w http.ResponseWriter, r *http.Request) {
	// Check database connectivity
	ctx := r.Context()
	err := db.PingContext(ctx)
	status := "healthy"
	if err != nil {
		status = "unhealthy"
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":   status,
		"database": err == nil,
		"time":     time.Now().Format(time.RFC3339),
	})
}

// listUsersHandler lists all users from the database
func listUsersHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// Query is automatically traced by the instrumented database driver
	rows, err := db.QueryContext(ctx, "SELECT id, name, email, created_at FROM users ORDER BY id")
	if err != nil {
		http.Error(w, jsonError("failed to query users"), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Name, &u.Email, &u.CreatedAt); err != nil {
			http.Error(w, jsonError("failed to scan user"), http.StatusInternalServerError)
			return
		}
		users = append(users, u)
	}

	if err := rows.Err(); err != nil {
		http.Error(w, jsonError("error iterating users"), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(users)
}

// createUserHandler creates a new user in the database
func createUserHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	var input struct {
		Name  string `json:"name"`
		Email string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, jsonError("invalid JSON"), http.StatusBadRequest)
		return
	}

	if input.Name == "" || input.Email == "" {
		http.Error(w, jsonError("name and email are required"), http.StatusBadRequest)
		return
	}

	// Insert is automatically traced
	result, err := db.ExecContext(ctx,
		"INSERT INTO users (name, email) VALUES (?, ?)",
		input.Name, input.Email,
	)
	if err != nil {
		http.Error(w, jsonError("failed to create user: "+err.Error()), http.StatusInternalServerError)
		return
	}

	id, _ := result.LastInsertId()

	// Fetch the created user
	var user User
	err = db.QueryRowContext(ctx,
		"SELECT id, name, email, created_at FROM users WHERE id = ?", id,
	).Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)
	if err != nil {
		http.Error(w, jsonError("failed to fetch created user"), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(user)
}

// getUserHandler gets a user by ID from the database
func getUserHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	idStr := r.PathValue("id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, jsonError("invalid user ID"), http.StatusBadRequest)
		return
	}

	// Query is automatically traced
	var user User
	err = db.QueryRowContext(ctx,
		"SELECT id, name, email, created_at FROM users WHERE id = ?", id,
	).Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)

	if err == sql.ErrNoRows {
		http.Error(w, jsonError("user not found"), http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, jsonError("failed to fetch user"), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

// updateUserHandler updates a user in the database
func updateUserHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	idStr := r.PathValue("id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, jsonError("invalid user ID"), http.StatusBadRequest)
		return
	}

	var input struct {
		Name  string `json:"name"`
		Email string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, jsonError("invalid JSON"), http.StatusBadRequest)
		return
	}

	// Update is automatically traced
	result, err := db.ExecContext(ctx,
		"UPDATE users SET name = ?, email = ? WHERE id = ?",
		input.Name, input.Email, id,
	)
	if err != nil {
		http.Error(w, jsonError("failed to update user: "+err.Error()), http.StatusInternalServerError)
		return
	}

	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		http.Error(w, jsonError("user not found"), http.StatusNotFound)
		return
	}

	// Fetch updated user
	var user User
	err = db.QueryRowContext(ctx,
		"SELECT id, name, email, created_at FROM users WHERE id = ?", id,
	).Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt)
	if err != nil {
		http.Error(w, jsonError("failed to fetch updated user"), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

// deleteUserHandler deletes a user from the database
func deleteUserHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	idStr := r.PathValue("id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, jsonError("invalid user ID"), http.StatusBadRequest)
		return
	}

	// Delete is automatically traced
	result, err := db.ExecContext(ctx, "DELETE FROM users WHERE id = ?", id)
	if err != nil {
		http.Error(w, jsonError("failed to delete user"), http.StatusInternalServerError)
		return
	}

	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		http.Error(w, jsonError("user not found"), http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "user deleted successfully",
	})
}

// jokeHandler demonstrates making an instrumented downstream HTTP call
func jokeHandler(w http.ResponseWriter, r *http.Request) {
	// Use the instrumented HTTP client for automatic trace propagation
	client := httpagent.NewClient(&http.Client{
		Timeout: 10 * time.Second,
	})

	// Create request with context to propagate trace
	req, err := http.NewRequestWithContext(r.Context(), "GET", "https://official-joke-api.appspot.com/random_joke", nil)
	if err != nil {
		http.Error(w, jsonError("failed to create request"), http.StatusInternalServerError)
		return
	}

	resp, err := client.Do(req)
	if err != nil {
		http.Error(w, jsonError("failed to fetch joke"), http.StatusInternalServerError)
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		http.Error(w, jsonError("failed to read response"), http.StatusInternalServerError)
		return
	}

	var joke struct {
		Setup     string `json:"setup"`
		Punchline string `json:"punchline"`
	}
	if err := json.Unmarshal(body, &joke); err != nil {
		http.Error(w, jsonError("failed to parse joke"), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"setup":     joke.Setup,
		"punchline": joke.Punchline,
	})
}

// jsonError returns a JSON error response
func jsonError(msg string) string {
	return fmt.Sprintf(`{"error":"%s"}`, msg)
}

// Alternative patterns for reference (not used in this example):

// Example: Wrap an existing http.ServeMux
func exampleWrapHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/data", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("data"))
	})
	// Wrap the entire mux for instrumentation
	return nethttp.WrapHandler(mux)
}

// Example: Wrap individual handlers
func exampleIndividualHandler() {
	handler := nethttp.Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("instrumented handler"))
	}), "/custom-endpoint")
	http.Handle("/custom-endpoint", handler)
}

// Example: Use Middleware pattern
func exampleMiddleware() http.Handler {
	baseHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("middleware example"))
	})
	return nethttp.Middleware("my-operation")(baseHandler)
}

// Example: Context propagation helpers
func exampleContextPropagation(ctx context.Context, w http.ResponseWriter, r *http.Request) {
	// Extract trace context from incoming request
	ctx = nethttp.ExtractContext(ctx, r)

	// Inject trace context into outgoing request
	outReq, _ := http.NewRequestWithContext(ctx, "GET", "http://downstream-service/api", nil)
	nethttp.InjectContext(ctx, outReq)
}
