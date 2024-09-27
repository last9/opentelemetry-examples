package users

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"strconv"

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

	db, err := sql.Open(driverName, dsnName)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %v", err)
	}

	// Record stats to expose metrics
	if err := otelsql.RecordStats(db); err != nil {
		return nil, err
	}

	return db, nil
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

// Implement UpdateUser and DeleteUser methods similarly,
// updating Redis cache accordingly

// Helper functions (implement these according to your database setup)
func fetchUsersFromDatabase() ([]User, error) {
	// Implement database fetch logic
	return nil, nil // Temporary placeholder
}

func fetchUserFromDatabase(id string) (*User, error) {
	// Implement database fetch logic
	return nil, nil // Temporary placeholder
}

func createUserInDatabase(user *User) error {
	// Implement database creation logic
	db, err := initDB()
	if err != nil {
		log.Printf("failed to initialize database: %v", err)
		return err
	}
	defer db.Close()

	// CREATE TABLE users (
	// 	id SERIAL PRIMARY KEY,
	// 	name VARCHAR(255) NOT NULL,
	// 	email VARCHAR(255) NOT NULL UNIQUE
	// );
	stmt, err := db.Prepare("INSERT INTO users (id, name, email) VALUES ($1, $2, $3)")
	if err != nil {
		log.Printf("failed to prepare statement: %v", err)
		return fmt.Errorf("failed to prepare statement: %v", err)
	}
	defer stmt.Close()

	// Execute the SQL statement
	_, err = stmt.Exec(user.ID, user.Name, user.Email)
	if err != nil {
		log.Printf("failed to insert user: %v", err)
		return fmt.Errorf("failed to insert user: %v", err)
	}
	return nil // Temporary placeholder
}

// Add this method to the UsersController struct
func (c *UsersController) UpdateUser(ctx context.Context, id int, name string) *User {
	// Implementation here
	user, err := c.GetUser(ctx, strconv.Itoa(id))
	if err != nil {
		return nil
	}
	if user != nil {
		user.Name = name
		// update user in database
		db, err := initDB()
		if err != nil {
			log.Printf("failed to initialize database: %v", err)
			return nil
		}
		defer db.Close()
		stmt, err := db.Prepare("UPDATE users SET name = $1 WHERE id = $2")
		if err != nil {
			log.Printf("failed to prepare statement: %v", err)
			return nil
		}
		defer stmt.Close()

		_, err = stmt.Exec(user.Name, user.ID)
		if err != nil {
			log.Printf("failed to update user: %v", err)
			return nil
		}
	}
	return user
}

func (uc *UsersController) DeleteUser(ctx context.Context, id int) error {
	// Implement user deletion logic here
	db, err := initDB()
	if err != nil {
		log.Printf("failed to initialize database: %v", err)
		return fmt.Errorf("failed to initialize database: %v", err)
	}
	defer db.Close()

	stmt, err := db.Prepare("DELETE FROM users WHERE id = $1")
	if err != nil {
		log.Printf("failed to prepare statement: %v", err)
		return fmt.Errorf("failed to prepare statement: %v", err)
	}
	defer stmt.Close()

	_, err = stmt.Exec(id)
	if err != nil {
		log.Printf("failed to delete user: %v", err)
		return fmt.Errorf("failed to delete user: %v", err)
	}

	return nil
}
