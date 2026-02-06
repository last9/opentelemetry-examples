package users

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"strconv"

	dbagent "github.com/last9/go-agent/integrations/database"
	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"
)

var dsnName = "postgres://postgres:postgres@localhost/otel_demo?sslmode=disable"

type UsersController struct {
	redisClient *redis.Client
}

func initDB() (*sql.DB, error) {
	// Open database with go-agent (automatic instrumentation)
	db, err := dbagent.Open(dbagent.Config{
		DriverName:   "postgres",
		DSN:          dsnName,
		DatabaseName: "otel_demo",
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %v", err)
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
func (c *UsersController) UpdateUser(id int, name string) *User {
	// Implementation here
	ctx := context.Background() // Create a context
	user, err := c.GetUser(ctx, strconv.Itoa(id))
	if err != nil {
		return nil
	}
	if user != nil {
		user.Name = name
		// Update user in storage
	}
	return user
}

func (uc *UsersController) DeleteUser(ctx context.Context, id int) error {
	// Implement user deletion logic here
	return nil
}
