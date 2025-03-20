package users

import (
	"context"
	"fmt"
	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
)

type UsersController struct {
	db *sqlx.DB
}

func NewUsersController(db *sqlx.DB) *UsersController {
	return &UsersController{db: db}
}

func (c *UsersController) GetUsers(ctx context.Context) ([]User, error) {
	var users []User
	err := c.db.SelectContext(ctx, &users, "SELECT * FROM users")
	if err != nil {
		return nil, fmt.Errorf("failed to get users: %v", err)
	}
	return users, nil
}

func (c *UsersController) GetUser(ctx context.Context, id string) (*User, error) {
	var user User
	err := c.db.GetContext(ctx, &user, "SELECT * FROM users WHERE id = $1", id)
	if err != nil {
		return nil, fmt.Errorf("failed to get user: %v", err)
	}
	return &user, nil
}

func (c *UsersController) CreateUser(ctx context.Context, user *User) error {
	user.ID = uuid.New().String()
	_, err := c.db.NamedExecContext(ctx, 
		"INSERT INTO users (id, name, email) VALUES (:id, :name, :email)",
		user)
	if err != nil {
		return fmt.Errorf("failed to create user: %v", err)
	}
	return nil
}

func (c *UsersController) UpdateUser(ctx context.Context, id string, user *User) error {
	user.ID = id
	result, err := c.db.NamedExecContext(ctx,
		"UPDATE users SET name = :name, email = :email WHERE id = :id",
		user)
	if err != nil {
		return fmt.Errorf("failed to update user: %v", err)
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("error checking rows affected: %v", err)
	}
	if rows == 0 {
		return fmt.Errorf("user not found")
	}
	return nil
}

func (c *UsersController) DeleteUser(ctx context.Context, id string) error {
	result, err := c.db.ExecContext(ctx, "DELETE FROM users WHERE id = $1", id)
	if err != nil {
		return fmt.Errorf("failed to delete user: %v", err)
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("error checking rows affected: %v", err)
	}
	if rows == 0 {
		return fmt.Errorf("user not found")
	}
	return nil
}
