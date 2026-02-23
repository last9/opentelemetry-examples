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
	usersJSON, err := c.redisClient.Get(ctx, "users").Result()
	if err == nil {
		var users []User
		err = json.Unmarshal([]byte(usersJSON), &users)
		if err == nil {
			return users, nil
		}
	}

	users, err := fetchUsersFromDatabase()
	if err != nil {
		return nil, err
	}

	jsonUsers, _ := json.Marshal(users)
	c.redisClient.Set(ctx, "users", jsonUsers, 0)

	return users, nil
}

func (c *UsersController) GetUser(ctx context.Context, id string) (*User, error) {
	userJSON, err := c.redisClient.Get(ctx, fmt.Sprintf("user:%s", id)).Result()
	if err == nil {
		var user User
		err = json.Unmarshal([]byte(userJSON), &user)
		if err == nil {
			return &user, nil
		}
	}

	user, err := fetchUserFromDatabase(id)
	if err != nil {
		return nil, err
	}

	jsonUser, _ := json.Marshal(user)
	c.redisClient.Set(ctx, fmt.Sprintf("user:%s", id), jsonUser, 0)

	return user, nil
}

func (c *UsersController) CreateUser(ctx context.Context, user *User) error {
	err := createUserInDatabase(user)
	if err != nil {
		return err
	}

	userJSON, err := json.Marshal(user)
	if err != nil {
		return err
	}
	c.redisClient.Set(ctx, fmt.Sprintf("user:%s", user.ID), userJSON, 0)

	c.redisClient.Del(ctx, "users")

	return nil
}

func (c *UsersController) UpdateUser(ctx context.Context, id int, name string) *User {
	user, err := c.GetUser(ctx, strconv.Itoa(id))
	if err != nil {
		return nil
	}
	if user != nil {
		user.Name = name
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

		// Update Redis cache
		userJSON, _ := json.Marshal(user)
		c.redisClient.Set(ctx, fmt.Sprintf("user:%s", user.ID), userJSON, 0)
		c.redisClient.Del(ctx, "users")
	}
	return user
}

func (uc *UsersController) DeleteUser(ctx context.Context, id int) error {
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

	// Update Redis cache
	uc.redisClient.Del(ctx, fmt.Sprintf("user:%d", id))
	uc.redisClient.Del(ctx, "users")

	return nil
}

func fetchUsersFromDatabase() ([]User, error) {
	db, err := initDB()
	if err != nil {
		return nil, fmt.Errorf("failed to initialize database: %v", err)
	}
	defer db.Close()

	rows, err := db.Query("SELECT id, name, email FROM users")
	if err != nil {
		return nil, fmt.Errorf("failed to fetch users: %v", err)
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var user User
		err := rows.Scan(&user.ID, &user.Name, &user.Email)
		if err != nil {
			return nil, fmt.Errorf("failed to scan user: %v", err)
		}
		users = append(users, user)
	}

	return users, nil
}

func fetchUserFromDatabase(id string) (*User, error) {
	db, err := initDB()
	if err != nil {
		return nil, fmt.Errorf("failed to initialize database: %v", err)
	}
	defer db.Close()

	var user User
	err = db.QueryRow("SELECT id, name, email FROM users WHERE id = $1", id).Scan(&user.ID, &user.Name, &user.Email)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("user not found")
		}
		return nil, fmt.Errorf("failed to fetch user: %v", err)
	}

	return &user, nil
}

func createUserInDatabase(user *User) error {
	db, err := initDB()
	if err != nil {
		log.Printf("failed to initialize database: %v", err)
		return err
	}
	defer db.Close()

	stmt, err := db.Prepare("INSERT INTO users (id, name, email) VALUES ($1, $2, $3)")
	if err != nil {
		log.Printf("failed to prepare statement: %v", err)
		return fmt.Errorf("failed to prepare statement: %v", err)
	}
	defer stmt.Close()

	_, err = stmt.Exec(user.ID, user.Name, user.Email)
	if err != nil {
		log.Printf("failed to insert user: %v", err)
		return fmt.Errorf("failed to insert user: %v", err)
	}
	return nil
}
