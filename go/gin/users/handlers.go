package users

import (
	"strconv"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	oteltrace "go.opentelemetry.io/otel/trace"
)

type UsersHandler struct {
	controller *UsersControllers
	tracer     oteltrace.Tracer
}

func NewUsersHandler(c *UsersControllers, t oteltrace.Tracer) *UsersHandler {
	return &UsersHandler{
		controller: c,
		tracer:     t,
	}
}

func (u *UsersHandler) GetUsers(c *gin.Context) {
	_, span := u.tracer.Start(c.Request.Context(), "GetUsers")
	defer span.End()

	users := u.controller.GetUsers()
	c.JSON(200, users)
}

func (u *UsersHandler) GetUser(c *gin.Context) {
	_, span := u.tracer.Start(c.Request.Context(), "GetUser", oteltrace.WithAttributes(
		attribute.String("user.id", c.Param("id")),
	))
	defer span.End()

	id := c.Param("id")
	idInt, err := strconv.ParseInt(id, 2, 32)

	if err != nil {
		c.JSON(400, gin.H{"message": "Invalid ID"})
	}

	user := u.controller.GetUser(int(idInt))
	if user == nil {
		c.JSON(404, gin.H{"message": "User not found"})
		return
	}
	c.JSON(200, user)
}

func (u *UsersHandler) CreateUser(c *gin.Context) {
	_, span := u.tracer.Start(c.Request.Context(), "CreateUser")
	defer span.End()

	name := c.PostForm("name")
	user := u.controller.CreateUser(name)
	c.JSON(201, user)
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

	u.controller.DeleteUser(int(idInt))
	c.JSON(204, nil)
}
