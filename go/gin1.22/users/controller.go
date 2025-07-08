package users

import (
	"context"
	"errors"
	"fmt"
	"sync"
)

type UsersController struct {
	users map[string]*User
	mutex sync.RWMutex
}

func NewUsersController() *UsersController {
	controller := &UsersController{
		users: make(map[string]*User),
		mutex: sync.RWMutex{},
	}
	
	// Initialize with some sample data
	sampleUsers := []*User{
		{ID: "1", Name: "John Doe", Email: "john@example.com"},
		{ID: "2", Name: "Jane Smith", Email: "jane@example.com"},
		{ID: "3", Name: "Bob Johnson", Email: "bob@example.com"},
	}
	
	for _, user := range sampleUsers {
		controller.users[user.ID] = user
	}
	
	return controller
}

func (c *UsersController) GetUsers(ctx context.Context) ([]User, error) {
	c.mutex.RLock()
	defer c.mutex.RUnlock()
	
	users := make([]User, 0, len(c.users))
	for _, user := range c.users {
		users = append(users, *user)
	}
	
	return users, nil
}

func (c *UsersController) GetUser(ctx context.Context, id string) (*User, error) {
	c.mutex.RLock()
	defer c.mutex.RUnlock()
	
	user, exists := c.users[id]
	if !exists {
		return nil, errors.New("user not found")
	}
	
	// Return a copy to prevent external modification
	userCopy := *user
	return &userCopy, nil
}

func (c *UsersController) CreateUser(ctx context.Context, user *User) error {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	
	if user.ID == "" {
		return errors.New("user ID cannot be empty")
	}
	
	if user.Name == "" {
		return errors.New("user name cannot be empty")
	}
	
	if user.Email == "" {
		return errors.New("user email cannot be empty")
	}
	
	// Check if user already exists
	if _, exists := c.users[user.ID]; exists {
		return errors.New("user already exists")
	}
	
	// Store a copy
	userCopy := *user
	c.users[user.ID] = &userCopy
	
	return nil
}

func (c *UsersController) UpdateUser(ctx context.Context, id string, user *User) (*User, error) {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	
	existingUser, exists := c.users[id]
	if !exists {
		return nil, errors.New("user not found")
	}
	
	// Update fields if provided
	if user.Name != "" {
		existingUser.Name = user.Name
	}
	if user.Email != "" {
		existingUser.Email = user.Email
	}
	
	// Return a copy
	userCopy := *existingUser
	return &userCopy, nil
}

func (c *UsersController) DeleteUser(ctx context.Context, id string) error {
	c.mutex.Lock()
	defer c.mutex.Unlock()
	
	if _, exists := c.users[id]; !exists {
		return fmt.Errorf("user with ID %s not found", id)
	}
	
	delete(c.users, id)
	return nil
}