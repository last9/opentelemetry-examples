package users

import (
	"log"
	"strconv"

	"github.com/gin-gonic/gin"
)

type UsersHandler struct {
	controller *UsersController
}

func NewUsersHandler(c *UsersController) *UsersHandler {
	return &UsersHandler{
		controller: c,
	}
}

func (u *UsersHandler) GetUsers(c *gin.Context) {
	// go-agent automatically creates spans for Gin handlers
	users, err := u.controller.GetUsers(c.Request.Context())
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to fetch users"})
		return
	}
	c.JSON(200, users)
}

func (u *UsersHandler) GetUser(c *gin.Context) {
	id := c.Param("id")
	user, err := u.controller.GetUser(c.Request.Context(), id)
	if err != nil {
		c.JSON(404, gin.H{"message": "User not found"})
		return
	}
	c.JSON(200, user)
}

func (u *UsersHandler) CreateUser(c *gin.Context) {
	log.Println("Creating user")
	var newUser User
	if err := c.ShouldBindJSON(&newUser); err != nil {
		c.JSON(400, gin.H{"error": "Invalid input data"})
		return
	}
	err := u.controller.CreateUser(c.Request.Context(), &newUser)
	if err != nil {
		c.JSON(500, gin.H{"error": err})
		return
	}
	c.JSON(201, nil)
}

func (u *UsersHandler) UpdateUser(c *gin.Context) {
	id := c.Param("id")
	idInt, err := strconv.ParseInt(id, 10, 32)
	if err != nil {
		c.JSON(400, gin.H{"message": "Invalid ID"})
		return
	}

	name := c.PostForm("name")
	user := u.controller.UpdateUser(int(idInt), name)
	if user == nil {
		c.JSON(404, gin.H{"message": "User not found"})
		return
	}
	c.JSON(200, user)
}

func (u *UsersHandler) DeleteUser(c *gin.Context) {
	id := c.Param("id")
	idInt, err := strconv.ParseInt(id, 10, 32)
	if err != nil {
		c.JSON(400, gin.H{"message": "Invalid ID"})
		return
	}

	err = u.controller.DeleteUser(c.Request.Context(), int(idInt))
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to delete user"})
		return
	}
	c.JSON(204, nil)
}
