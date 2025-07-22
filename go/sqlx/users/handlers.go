package users

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	oteltrace "go.opentelemetry.io/otel/trace"
	"go.opentelemetry.io/otel/codes"
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
	ctx := c.Request.Context()
	ctx, span := u.tracer.Start(ctx, "update-user")
	defer span.End()

	id := c.Param("id")
	
	// Create a User object from the request body
	var user User
	if err := c.ShouldBindJSON(&user); err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Pass the id and user pointer to UpdateUser
	if err := u.controller.UpdateUser(ctx, id, &user); err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User updated successfully"})
}

func (u *UsersHandler) DeleteUser(c *gin.Context) {
	ctx := c.Request.Context()
	ctx, span := u.tracer.Start(ctx, "delete-user")
	defer span.End()

	// Get the ID directly as a string, no conversion needed
	id := c.Param("id")
	
	if err := u.controller.DeleteUser(ctx, id); err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "User deleted successfully"})
}
