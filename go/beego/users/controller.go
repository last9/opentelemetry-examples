package users

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strconv"

	_ "github.com/lib/pq"
	"go.nhat.io/otelsql"
	semconv "go.opentelemetry.io/otel/semconv/v1.4.0"

	"github.com/redis/go-redis/v9"

	orm "github.com/beego/beego/v2/client/orm"
	otelorm "github.com/beego/beego/v2/client/orm/filter/opentelemetry"
)

var dsnName = "postgres://postgres:postgres@localhost/otel_demo?sslmode=disable"

type UsersController struct {
	redisClient *redis.Client
}

func init() {
	// Register the Beego ORM OpenTelemetry filter
	orm.AddGlobalFilterChain(otelorm.NewFilterChainBuilder().FilterChain)
}

func initDB() (*sql.DB, error) {
	driverName, err := otelsql.Register("postgres",
		otelsql.AllowRoot(),
		otelsql.TraceQueryWithoutArgs(),
		otelsql.TraceRowsClose(),
		otelsql.TraceRowsAffected(),
		otelsql.WithDatabaseName("otel_demo"),
		otelsql.WithSystem(semconv.DBSystemPostgreSQL),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to register driver: %v", err)
	}

	db, err := sql.Open(driverName, dsnName)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %v", err)
	}

	if err := otelsql.RecordStats(db); err != nil {
		return nil, err
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

	users, err := fetchUsersFromDatabase(ctx)
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

	user, err := fetchUserFromDatabase(ctx, id)
	if err != nil {
		return nil, err
	}

	jsonUser, _ := json.Marshal(user)
	c.redisClient.Set(ctx, fmt.Sprintf("user:%s", id), jsonUser, 0)

	return user, nil
}

func (c *UsersController) CreateUser(ctx context.Context, user *User) error {
	err := createUserInDatabase(ctx, user)
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
			return nil
		}
		defer db.Close()
		stmt, err := db.PrepareContext(ctx, "UPDATE users SET name = $1 WHERE id = $2")
		if err != nil {
			return nil
		}
		defer stmt.Close()

		_, err = stmt.ExecContext(ctx, user.Name, user.ID)
		if err != nil {
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
		return fmt.Errorf("failed to initialize database: %v", err)
	}
	defer db.Close()

	stmt, err := db.PrepareContext(ctx, "DELETE FROM users WHERE id = $1")
	if err != nil {
		return fmt.Errorf("failed to prepare statement: %v", err)
	}
	defer stmt.Close()

	_, err = stmt.ExecContext(ctx, id)
	if err != nil {
		return fmt.Errorf("failed to delete user: %v", err)
	}

	// Update Redis cache
	uc.redisClient.Del(ctx, fmt.Sprintf("user:%d", id))
	uc.redisClient.Del(ctx, "users")

	return nil
}

func fetchUsersFromDatabase(ctx context.Context) ([]User, error) {
	db, err := initDB()
	if err != nil {
		return nil, fmt.Errorf("failed to initialize database: %v", err)
	}
	defer db.Close()

	rows, err := db.QueryContext(ctx, "SELECT id, name, email FROM users")
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

func fetchUserFromDatabase(ctx context.Context, id string) (*User, error) {
	db, err := initDB()
	if err != nil {
		return nil, fmt.Errorf("failed to initialize database: %v", err)
	}
	defer db.Close()

	var user User
	err = db.QueryRowContext(ctx, "SELECT id, name, email FROM users WHERE id = $1", id).Scan(&user.ID, &user.Name, &user.Email)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("user not found")
		}
		return nil, fmt.Errorf("failed to fetch user: %v", err)
	}

	return &user, nil
}

func createUserInDatabase(ctx context.Context, user *User) error {
	db, err := initDB()
	if err != nil {
		return err
	}
	defer db.Close()

	stmt, err := db.PrepareContext(ctx, "INSERT INTO users (id, name, email) VALUES ($1, $2, $3)")
	if err != nil {
		return fmt.Errorf("failed to prepare statement: %v", err)
	}
	defer stmt.Close()

	_, err = stmt.ExecContext(ctx, user.ID, user.Name, user.Email)
	if err != nil {
		return fmt.Errorf("failed to insert user: %v", err)
	}
	return nil
}
