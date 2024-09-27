package users

import (
	"strconv"

	"github.com/kataras/iris/v12"
	"go.opentelemetry.io/otel/attribute"
	oteltrace "go.opentelemetry.io/otel/trace"
)

type UsersHandler struct {
	controller *UsersController
	tracer     oteltrace.Tracer
}

func NewUsersHandler(c *UsersController, t oteltrace.Tracer) *UsersHandler {
	return &UsersHandler{
		controller: c,
		tracer:     t,
	}
}

func (u *UsersHandler) GetUsers(ctx iris.Context) {
	traceCtx, span := u.tracer.Start(ctx.Request().Context(), "GetUsers")
	defer span.End()

	users, err := u.controller.GetUsers(traceCtx)
	if err != nil {
		ctx.StatusCode(iris.StatusInternalServerError)
		ctx.JSON(iris.Map{"error": "Failed to fetch users"})
		return
	}

	ctx.JSON(users)
}

func (u *UsersHandler) GetUser(ctx iris.Context) {
	id := ctx.Params().Get("id")
	traceCtx, span := u.tracer.Start(ctx.Request().Context(), "GetUser", oteltrace.WithAttributes(
		attribute.String("user.id", id),
	))
	defer span.End()

	user, err := u.controller.GetUser(traceCtx, id)
	if err != nil {
		ctx.StatusCode(iris.StatusNotFound)
		ctx.JSON(iris.Map{"message": "User not found"})
		return
	}
	ctx.JSON(user)
}

func (u *UsersHandler) CreateUser(ctx iris.Context) {
	traceCtx, span := u.tracer.Start(ctx.Request().Context(), "CreateUser")
	defer span.End()

	var newUser User
	if err := ctx.ReadJSON(&newUser); err != nil {
		ctx.StatusCode(iris.StatusBadRequest)
		ctx.JSON(iris.Map{"error": "Invalid input data"})
		return
	}

	err := u.controller.CreateUser(traceCtx, &newUser)
	if err != nil {
		ctx.StatusCode(iris.StatusInternalServerError)
		ctx.JSON(iris.Map{"error": "Failed to create user"})
		return
	}

	ctx.StatusCode(iris.StatusCreated)
	ctx.JSON(newUser)
}

func (u *UsersHandler) UpdateUser(ctx iris.Context) {
	id := ctx.Params().Get("id")
	traceCtx, span := u.tracer.Start(ctx.Request().Context(), "UpdateUser", oteltrace.WithAttributes(
		attribute.String("user.id", id),
	))
	defer span.End()

	idInt, err := strconv.ParseInt(id, 10, 32)
	if err != nil {
		ctx.StatusCode(iris.StatusBadRequest)
		ctx.JSON(iris.Map{"message": "Invalid ID"})
		return
	}

	var updateData struct {
		Name string `json:"name"`
	}
	if err := ctx.ReadJSON(&updateData); err != nil {
		ctx.StatusCode(iris.StatusBadRequest)
		ctx.JSON(iris.Map{"message": "Invalid input data"})
		return
	}

	user := u.controller.UpdateUser(traceCtx, int(idInt), updateData.Name)
	if user == nil {
		ctx.StatusCode(iris.StatusNotFound)
		ctx.JSON(iris.Map{"message": "User not found"})
		return
	}

	ctx.JSON(user)
}

func (u *UsersHandler) DeleteUser(ctx iris.Context) {
	id := ctx.Params().Get("id")
	traceCtx, span := u.tracer.Start(ctx.Request().Context(), "DeleteUser", oteltrace.WithAttributes(
		attribute.String("user.id", id),
	))
	defer span.End()

	idInt, err := strconv.ParseInt(id, 10, 32)
	if err != nil {
		ctx.StatusCode(iris.StatusBadRequest)
		ctx.JSON(iris.Map{"message": "Invalid ID"})
		return
	}

	err = u.controller.DeleteUser(traceCtx, int(idInt))
	if err != nil {
		ctx.StatusCode(iris.StatusInternalServerError)
		ctx.JSON(iris.Map{"error": "Failed to delete user"})
		return
	}
	ctx.StatusCode(iris.StatusNoContent)
}
