package users

import (
	"gin_example/common"
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
		// Record detailed exception information
		common.RecordExceptionInSpan(c, "Failed to fetch users", 
			"error_type", "database_error",
			"operation", "get_users",
			"details", err.Error())
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
		// Record detailed exception information
		common.RecordExceptionInSpan(c, "User not found", 
			"error_type", "not_found",
			"operation", "get_user",
			"user_id", id,
			"details", err.Error())
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
		// Record validation error
		common.RecordExceptionInSpan(c, "Invalid input data", 
			"error_type", "validation_error",
			"operation", "create_user",
			"details", err.Error())
		c.JSON(400, gin.H{"error": "Invalid input data"})
		return
	}
	err := u.controller.CreateUser(c.Request.Context(), &newUser)
	if err != nil {
		// Record database error with stack trace
		common.RecordExceptionWithStack(c, err,
			"operation", "create_user",
			"user_name", newUser.Name,
			"user_email", newUser.Email)
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
	idInt, err := strconv.ParseInt(id, 10, 32) // Fixed base from 2 to 10

	if err != nil {
		// Record validation error
		common.RecordExceptionInSpan(c, "Invalid user ID format", 
			"error_type", "validation_error",
			"operation", "update_user",
			"user_id", id,
			"details", err.Error())
		c.JSON(400, gin.H{"message": "Invalid ID"})
		return
	}

	name := c.PostForm("name")
	user := u.controller.UpdateUser(int(idInt), name)
	if user == nil {
		// Record not found error
		common.RecordExceptionInSpan(c, "User not found for update", 
			"error_type", "not_found",
			"operation", "update_user",
			"user_id", idInt)
		c.JSON(404, gin.H{"message": "User not found"})
		return
	}
	c.JSON(200, user)
}

func (u *UsersHandler) DeleteUser(c *gin.Context) {
	_, span := u.tracer.Start(c.Request.Context(), "DeleteUser", oteltrace.WithAttributes( // Fixed span name
		attribute.String("user.id", c.Param("id")),
	))
	defer span.End()

	id := c.Param("id")
	idInt, err := strconv.ParseInt(id, 10, 32) // Fixed base from 2 to 10

	if err != nil {
		// Record validation error
		common.RecordExceptionInSpan(c, "Invalid user ID format", 
			"error_type", "validation_error",
			"operation", "delete_user",
			"user_id", id,
			"details", err.Error())
		c.JSON(400, gin.H{"message": "Invalid ID"})
		return
	}

	err = u.controller.DeleteUser(c.Request.Context(), int(idInt))
	if err != nil {
		// Record database error with stack trace
		common.RecordExceptionWithStack(c, err,
			"operation", "delete_user",
			"user_id", idInt)
		c.JSON(500, gin.H{"error": "Failed to delete user"})
		return
	}
	c.JSON(204, nil)
}
