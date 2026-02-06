package database

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"time"

	_ "github.com/lib/pq"
	dbagent "github.com/last9/go-agent/integrations/database"
)

type DB struct {
	conn *sql.DB
}

type User struct {
	ID        int
	Name      string
	Email     string
	CreatedAt time.Time
	GreetCount int
}

// NewDB creates a new database connection with go-agent instrumentation
func NewDB(dsn string) (*DB, error) {
	// Open the database connection with go-agent instrumentation
	db, err := dbagent.Open(dbagent.Config{
		DriverName:   "postgres",
		DSN:          dsn,
		DatabaseName: "grpc_gateway",
	})
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Configure connection pool
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	// Test the connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	log.Println("✓ Database connection established with go-agent instrumentation")

	return &DB{conn: db}, nil
}

// InitSchema creates the users table if it doesn't exist
func (db *DB) InitSchema(ctx context.Context) error {
	query := `
	CREATE TABLE IF NOT EXISTS users (
		id SERIAL PRIMARY KEY,
		name VARCHAR(255) NOT NULL,
		email VARCHAR(255) UNIQUE NOT NULL,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		greet_count INTEGER DEFAULT 0
	);
	CREATE INDEX IF NOT EXISTS idx_users_name ON users(name);
	CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
	`

	_, err := db.conn.ExecContext(ctx, query)
	if err != nil {
		return fmt.Errorf("failed to create schema: %w", err)
	}

	log.Println("✓ Database schema initialized")
	return nil
}

// GetOrCreateUser gets a user by name or creates if doesn't exist
func (db *DB) GetOrCreateUser(ctx context.Context, name string) (*User, error) {
	// Try to get existing user
	user, err := db.GetUserByName(ctx, name)
	if err == nil {
		return user, nil
	}

	// User doesn't exist, create new one
	if err == sql.ErrNoRows {
		email := fmt.Sprintf("%s@example.com", name)
		return db.CreateUser(ctx, name, email)
	}

	return nil, err
}

// GetUserByName retrieves a user by name
func (db *DB) GetUserByName(ctx context.Context, name string) (*User, error) {
	query := `SELECT id, name, email, created_at, greet_count FROM users WHERE name = $1`

	var user User
	err := db.conn.QueryRowContext(ctx, query, name).Scan(
		&user.ID,
		&user.Name,
		&user.Email,
		&user.CreatedAt,
		&user.GreetCount,
	)

	if err != nil {
		return nil, err
	}

	return &user, nil
}

// CreateUser creates a new user
func (db *DB) CreateUser(ctx context.Context, name, email string) (*User, error) {
	query := `
		INSERT INTO users (name, email, greet_count)
		VALUES ($1, $2, 0)
		RETURNING id, name, email, created_at, greet_count
	`

	var user User
	err := db.conn.QueryRowContext(ctx, query, name, email).Scan(
		&user.ID,
		&user.Name,
		&user.Email,
		&user.CreatedAt,
		&user.GreetCount,
	)

	if err != nil {
		return nil, fmt.Errorf("failed to create user: %w", err)
	}

	return &user, nil
}

// IncrementGreetCount increments the greet count for a user
func (db *DB) IncrementGreetCount(ctx context.Context, userID int) error {
	query := `UPDATE users SET greet_count = greet_count + 1 WHERE id = $1`

	result, err := db.conn.ExecContext(ctx, query, userID)
	if err != nil {
		return fmt.Errorf("failed to increment greet count: %w", err)
	}

	rows, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected: %w", err)
	}

	if rows == 0 {
		return fmt.Errorf("user not found")
	}

	return nil
}

// GetUserStats returns user statistics
func (db *DB) GetUserStats(ctx context.Context, userID int) (int, time.Time, error) {
	query := `SELECT greet_count, created_at FROM users WHERE id = $1`

	var greetCount int
	var createdAt time.Time

	err := db.conn.QueryRowContext(ctx, query, userID).Scan(&greetCount, &createdAt)
	if err != nil {
		return 0, time.Time{}, err
	}

	return greetCount, createdAt, nil
}

// GetTopUsers returns the top N users by greet count
func (db *DB) GetTopUsers(ctx context.Context, limit int) ([]User, error) {
	query := `
		SELECT id, name, email, created_at, greet_count
		FROM users
		ORDER BY greet_count DESC
		LIMIT $1
	`

	rows, err := db.conn.QueryContext(ctx, query, limit)
	if err != nil {
		return nil, fmt.Errorf("failed to query top users: %w", err)
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var user User
		if err := rows.Scan(&user.ID, &user.Name, &user.Email, &user.CreatedAt, &user.GreetCount); err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}
		users = append(users, user)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating rows: %w", err)
	}

	return users, nil
}

// Close closes the database connection
func (db *DB) Close() error {
	return db.conn.Close()
}
