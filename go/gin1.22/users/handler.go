package users

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

type UsersHandler struct {
	controller *UsersController
	tracer     trace.Tracer
}

func NewUsersHandler(controller *UsersController, tracer trace.Tracer) *UsersHandler {
	return &UsersHandler{
		controller: controller,
		tracer:     tracer,
	}
}

func (h *UsersHandler) GetUsers(c *gin.Context) {
	ctx, span := h.tracer.Start(c.Request.Context(), "GetUsers")
	defer span.End()

	users, err := h.controller.GetUsers(ctx)
	if err != nil {
		span.RecordError(err)
		span.SetAttributes(attribute.String("error", err.Error()))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch users"})
		return
	}

	span.SetAttributes(attribute.Int("users.count", len(users)))
	c.JSON(http.StatusOK, users)
}

func (h *UsersHandler) GetUser(c *gin.Context) {
	id := c.Param("id")
	ctx, span := h.tracer.Start(c.Request.Context(), "GetUser")
	defer span.End()

	span.SetAttributes(attribute.String("user.id", id))

	user, err := h.controller.GetUser(ctx, id)
	if err != nil {
		span.RecordError(err)
		span.SetAttributes(attribute.String("error", err.Error()))
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	span.SetAttributes(
		attribute.String("user.name", user.Name),
		attribute.String("user.email", user.Email),
	)
	c.JSON(http.StatusOK, user)
}

func (h *UsersHandler) CreateUser(c *gin.Context) {
	ctx, span := h.tracer.Start(c.Request.Context(), "CreateUser")
	defer span.End()

	var newUser User
	if err := c.ShouldBindJSON(&newUser); err != nil {
		span.RecordError(err)
		span.SetAttributes(attribute.String("error", "Invalid JSON input"))
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid input data"})
		return
	}

	span.SetAttributes(
		attribute.String("user.id", newUser.ID),
		attribute.String("user.name", newUser.Name),
		attribute.String("user.email", newUser.Email),
	)

	err := h.controller.CreateUser(ctx, &newUser)
	if err != nil {
		span.RecordError(err)
		span.SetAttributes(attribute.String("error", err.Error()))
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, newUser)
}

func (h *UsersHandler) UpdateUser(c *gin.Context) {
	id := c.Param("id")
	ctx, span := h.tracer.Start(c.Request.Context(), "UpdateUser")
	defer span.End()

	span.SetAttributes(attribute.String("user.id", id))

	var updateUser User
	if err := c.ShouldBindJSON(&updateUser); err != nil {
		span.RecordError(err)
		span.SetAttributes(attribute.String("error", "Invalid JSON input"))
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid input data"})
		return
	}

	user, err := h.controller.UpdateUser(ctx, id, &updateUser)
	if err != nil {
		span.RecordError(err)
		span.SetAttributes(attribute.String("error", err.Error()))
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	span.SetAttributes(
		attribute.String("user.name", user.Name),
		attribute.String("user.email", user.Email),
	)
	c.JSON(http.StatusOK, user)
}

func (h *UsersHandler) DeleteUser(c *gin.Context) {
	id := c.Param("id")
	ctx, span := h.tracer.Start(c.Request.Context(), "DeleteUser")
	defer span.End()

	span.SetAttributes(attribute.String("user.id", id))

	err := h.controller.DeleteUser(ctx, id)
	if err != nil {
		span.RecordError(err)
		span.SetAttributes(attribute.String("error", err.Error()))
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}