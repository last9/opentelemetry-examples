package users

import (
	"log"
	"strconv"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	oteltrace "go.opentelemetry.io/otel/trace"
)

type UsersHandler struct {
	controller *UsersController // Changed from UsersControllers to UsersController
	tracer     oteltrace.Tracer
}

func NewUsersHandler(c *UsersController, t oteltrace.Tracer) *UsersHandler {
	return &UsersHandler{
		controller: c,
		tracer:     t,
	}
}

func (u *UsersHandler) GetUsers(c *gin.Context) {
	ctx, span := u.tracer.Start(c.Request.Context(), "GetUsers")
	defer span.End()

	users, err := u.controller.GetUsers(ctx)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to fetch users"})
		return
	}
	c.JSON(200, users)
}

func (u *UsersHandler) GetUser(c *gin.Context) {
	_, span := u.tracer.Start(c.Request.Context(), "GetUser", oteltrace.WithAttributes(
		attribute.String("user.id", c.Param("id")),
	))
	defer span.End()

	id := c.Param("id")
	user, err := u.controller.GetUser(c.Request.Context(), id)
	if err != nil {
		c.JSON(404, gin.H{"message": "User not found"})
		return
	}
	c.JSON(200, user)
}

func (u *UsersHandler) CreateUser(c *gin.Context) {
	log.Println("here")
	_, span := u.tracer.Start(c.Request.Context(), "CreateUser")
	defer span.End()
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
	_, span := u.tracer.Start(c.Request.Context(), "UpdateUser", oteltrace.WithAttributes(
		attribute.String("user.id", c.Param("id")),
	))

	defer span.End()

	id := c.Param("id")
	idInt, err := strconv.ParseInt(id, 2, 32)

	if err != nil {
		c.JSON(400, gin.H{"message": "Invalid ID"})
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
	_, span := u.tracer.Start(c.Request.Context(), "UpdateUser", oteltrace.WithAttributes(
		attribute.String("user.id", c.Param("id")),
	))
	defer span.End()

	id := c.Param("id")
	idInt, err := strconv.ParseInt(id, 2, 32)

	if err != nil {
		c.JSON(400, gin.H{"message": "Invalid ID"})
	}

	err = u.controller.DeleteUser(c.Request.Context(), int(idInt))
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to delete user"})
		return
	}
	c.JSON(204, nil)
}
