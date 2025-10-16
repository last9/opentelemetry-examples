package users

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"

	_ "github.com/lib/pq"
	"go.nhat.io/otelsql"
	semconv "go.opentelemetry.io/otel/semconv/v1.4.0"

	"github.com/redis/go-redis/v9"
)

var dsnName = "postgres://postgres:postgres@localhost/otel_demo?sslmode=disable"

type UsersController struct {
	redisClient *redis.Client
}

func initDB() (*sql.DB, error) {
	driverName, err := otelsql.Register("postgres",
		// Read more about the options here: https://github.com/nhatthm/otelsql?tab=readme-ov-file#options
		otelsql.AllowRoot(),
		otelsql.TraceQueryWithoutArgs(),
		otelsql.TraceRowsClose(),
		otelsql.TraceRowsAffected(),
		otelsql.WithDatabaseName("otel_demo"), // database name
		otelsql.WithSystem(semconv.DBSystemPostgreSQL),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to register driver: %v", err)
	}

	dsn := getEnv("DATABASE_URL", dsnName)

	db, err := sql.Open(driverName, dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %v", err)
	}

	if err := ensureSchema(db); err != nil {
		return nil, fmt.Errorf("failed to ensure schema: %v", err)
	}

	// Record stats to expose metrics
	if err := otelsql.RecordStats(db); err != nil {
		return nil, err
	}

	return db, nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func ensureSchema(db *sql.DB) error {
	// Enable pgcrypto for gen_random_uuid and create users table
	_, err := db.Exec(`CREATE EXTENSION IF NOT EXISTS pgcrypto;`)
	if err != nil {
		return fmt.Errorf("failed to create extension: %w", err)
	}

	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS users (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		name TEXT NOT NULL,
		email TEXT NOT NULL UNIQUE
	);`)
	if err != nil {
		return fmt.Errorf("failed to create users table: %w", err)
	}
	return nil
}

func NewUsersController(redisClient *redis.Client) *UsersController {
	return &UsersController{redisClient: redisClient}
}

func (c *UsersController) GetUsers(ctx context.Context) ([]User, error) {
	// First, try to get users from Redis
	usersJSON, err := c.redisClient.Get(ctx, "users").Result()
	if err == nil {
		var users []User
		err = json.Unmarshal([]byte(usersJSON), &users)
		if err == nil {
			return users, nil
		}
	}

	// If not found in Redis or error occurred, fetch from database
	users, err := fetchUsersFromDatabase()
	if err != nil {
		return nil, err
	}

	// Store users in Redis for future requests
	jsonUsers, _ := json.Marshal(users)
	c.redisClient.Set(ctx, "users", jsonUsers, 0)

	return users, nil
}

func (c *UsersController) GetUser(ctx context.Context, id string) (*User, error) {
	// Try to get user from Redis
	userJSON, err := c.redisClient.Get(ctx, fmt.Sprintf("user:%s", id)).Result()
	if err == nil {
		var user User
		err = json.Unmarshal([]byte(userJSON), &user)
		if err == nil {
			return &user, nil
		}
	}

	// If not found in Redis or error occurred, fetch from database
	user, err := fetchUserFromDatabase(id)
	if err != nil {
		return nil, err
	}

	// Store user in Redis for future request
	jsonUser, _ := json.Marshal(user)
	c.redisClient.Set(ctx, fmt.Sprintf("user:%s", id), jsonUser, 0)

	return user, nil
}

func (c *UsersController) CreateUser(ctx context.Context, user *User) error {
	// Create user in database
    err := createUserInDatabase(user)
	if err != nil {
		return err
	}

	// Store user in Redis
	userJSON, err := json.Marshal(user)
	if err != nil {
		return err
	}
	c.redisClient.Set(ctx, fmt.Sprintf("user:%s", user.ID), userJSON, 0)

	// Update users list in Redis
	c.redisClient.Del(ctx, "users")

	return nil
}

// Helper functions
func fetchUsersFromDatabase() ([]User, error) {
	db, err := initDB()
	if err != nil {
		log.Printf("failed to initialize database: %v", err)
		return nil, err
	}
	defer db.Close()

	rows, err := db.Query("SELECT id::text, name, email FROM users ORDER BY name ASC")
	if err != nil {
		return nil, fmt.Errorf("failed to query users: %w", err)
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Name, &u.Email); err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}
		users = append(users, u)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("row iteration error: %w", err)
	}
	return users, nil
}

func fetchUserFromDatabase(id string) (*User, error) {
	db, err := initDB()
	if err != nil {
		log.Printf("failed to initialize database: %v", err)
		return nil, err
	}
	defer db.Close()

	var u User
	row := db.QueryRow("SELECT id::text, name, email FROM users WHERE id = $1::uuid", id)
	if err := row.Scan(&u.ID, &u.Name, &u.Email); err != nil {
		return nil, err
	}
	return &u, nil
}

func createUserInDatabase(user *User) error {
	db, err := initDB()
	if err != nil {
		log.Printf("failed to initialize database: %v", err)
		return err
	}
	defer db.Close()

	stmt, err := db.Prepare("INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id::text")
	if err != nil {
		log.Printf("failed to prepare statement: %v", err)
		return fmt.Errorf("failed to prepare statement: %v", err)
	}
	defer stmt.Close()

	if err := stmt.QueryRow(user.Name, user.Email).Scan(&user.ID); err != nil {
		log.Printf("failed to insert user: %v", err)
		return fmt.Errorf("failed to insert user: %v", err)
	}
	return nil
}

// UpdateUser updates a user by ID. Only non-nil fields are updated.
func (c *UsersController) UpdateUser(ctx context.Context, id string, name *string, email *string) (*User, error) {
	if name == nil && email == nil {
		return c.GetUser(ctx, id)
	}

	db, err := initDB()
	if err != nil {
		return nil, err
	}
	defer db.Close()

	setClauses := make([]string, 0, 2)
	args := make([]any, 0, 3)
	argPos := 1
	if name != nil {
		setClauses = append(setClauses, fmt.Sprintf("name=$%d", argPos))
		args = append(args, *name)
		argPos++
	}
	if email != nil {
		setClauses = append(setClauses, fmt.Sprintf("email=$%d", argPos))
		args = append(args, *email)
		argPos++
	}

	query := fmt.Sprintf("UPDATE users SET %s WHERE id = $%d::uuid RETURNING id::text, name, email", strings.Join(setClauses, ", "), argPos)
	args = append(args, id)

	var updated User
	if err := db.QueryRow(query, args...).Scan(&updated.ID, &updated.Name, &updated.Email); err != nil {
		return nil, err
	}

	// Update Redis cache
	jsonUser, _ := json.Marshal(updated)
	c.redisClient.Set(ctx, fmt.Sprintf("user:%s", updated.ID), jsonUser, 0)
	c.redisClient.Del(ctx, "users")

	return &updated, nil
}

// DeleteUser deletes a user by UUID string, updates Redis cache accordingly
func (uc *UsersController) DeleteUser(ctx context.Context, id string) error {
	db, err := initDB()
	if err != nil {
		return err
	}
	defer db.Close()

	if _, err := db.Exec("DELETE FROM users WHERE id = $1::uuid", id); err != nil {
		return err
	}

	uc.redisClient.Del(ctx, fmt.Sprintf("user:%s", id))
	uc.redisClient.Del(ctx, "users")
	return nil
}
