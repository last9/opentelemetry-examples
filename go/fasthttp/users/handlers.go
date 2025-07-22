package users

import (
	"context"
	"encoding/json"
	"strconv"

	"github.com/valyala/fasthttp"
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

func (u *UsersHandler) GetUsers(ctx *fasthttp.RequestCtx) {
	traceCtx, span := u.tracer.Start(context.Background(), "GetUsers")
	defer span.End()

	users, err := u.controller.GetUsers(traceCtx)
	if err != nil {
		ctx.SetStatusCode(fasthttp.StatusInternalServerError)
		ctx.SetBodyString(`{"error": "Failed to fetch users"}`)
		return
	}

	ctx.SetStatusCode(fasthttp.StatusOK)
	ctx.SetContentType("application/json")
	if err := json.NewEncoder(ctx).Encode(users); err != nil {
		ctx.SetStatusCode(fasthttp.StatusInternalServerError)
		ctx.SetBodyString(`{"error": "Failed to encode users"}`)
	}
}

func (u *UsersHandler) GetUser(ctx *fasthttp.RequestCtx) {
	traceCtx, span := u.tracer.Start(context.Background(), "GetUser", oteltrace.WithAttributes(
		attribute.String("user.id", string(ctx.QueryArgs().Peek("id"))),
	))
	defer span.End()

	id := string(ctx.QueryArgs().Peek("id"))
	user, err := u.controller.GetUser(traceCtx, id)
	if err != nil {
		ctx.SetStatusCode(fasthttp.StatusNotFound)
		ctx.SetBodyString(`{"message": "User not found"}`)
		return
	}
	ctx.SetStatusCode(fasthttp.StatusOK)
	ctx.SetContentType("application/json")
	if err := json.NewEncoder(ctx).Encode(user); err != nil {
		ctx.SetStatusCode(fasthttp.StatusInternalServerError)
		ctx.SetBodyString(`{"error": "Failed to encode user"}`)
	}
}

func (u *UsersHandler) CreateUser(ctx *fasthttp.RequestCtx) {
	traceCtx, span := u.tracer.Start(context.Background(), "CreateUser")
	defer span.End()

	var newUser User
	if err := json.Unmarshal(ctx.PostBody(), &newUser); err != nil {
		ctx.SetStatusCode(fasthttp.StatusBadRequest)
		ctx.SetBodyString(`{"error": "Invalid input data"}`)
		return
	}

	err := u.controller.CreateUser(traceCtx, &newUser)
	if err != nil {
		ctx.SetStatusCode(fasthttp.StatusInternalServerError)
		ctx.SetBodyString(`{"error": "Failed to create user"}`)
		return
	}

	ctx.SetStatusCode(fasthttp.StatusCreated)
}

func (u *UsersHandler) UpdateUser(ctx *fasthttp.RequestCtx) {
	traceCtx, span := u.tracer.Start(context.Background(), "UpdateUser", oteltrace.WithAttributes(
		attribute.String("user.id", string(ctx.QueryArgs().Peek("id"))),
	))
	defer span.End()

	id := string(ctx.QueryArgs().Peek("id"))
	idInt, err := strconv.ParseInt(id, 10, 32)
	if err != nil {
		ctx.SetStatusCode(fasthttp.StatusBadRequest)
		ctx.SetBodyString(`{"message": "Invalid ID"}`)
		return
	}

	var updateData struct {
		Name string `json:"name"`
	}
	if err := json.Unmarshal(ctx.PostBody(), &updateData); err != nil {
		ctx.SetStatusCode(fasthttp.StatusBadRequest)
		ctx.SetBodyString(`{"message": "Invalid input data"}`)
		return
	}

	user := u.controller.UpdateUser(traceCtx, int(idInt), updateData.Name)
	if user == nil {
		ctx.SetStatusCode(fasthttp.StatusNotFound)
		ctx.SetBodyString(`{"message": "User not found"}`)
		return
	}

	ctx.SetStatusCode(fasthttp.StatusOK)
	ctx.SetContentType("application/json")
	if err := json.NewEncoder(ctx).Encode(user); err != nil {
		ctx.SetStatusCode(fasthttp.StatusInternalServerError)
		ctx.SetBodyString(`{"error": "Failed to encode user"}`)
	}
}

func (u *UsersHandler) DeleteUser(ctx *fasthttp.RequestCtx) {
	traceCtx, span := u.tracer.Start(context.Background(), "DeleteUser", oteltrace.WithAttributes(
		attribute.String("user.id", string(ctx.QueryArgs().Peek("id"))),
	))
	defer span.End()

	id := string(ctx.QueryArgs().Peek("id"))
	idInt, err := strconv.ParseInt(id, 10, 32)
	if err != nil {
		ctx.SetStatusCode(fasthttp.StatusBadRequest)
		ctx.SetBodyString(`{"message": "Invalid ID"}`)
		return
	}

	err = u.controller.DeleteUser(traceCtx, int(idInt))
	if err != nil {
		ctx.SetStatusCode(fasthttp.StatusInternalServerError)
		ctx.SetBodyString(`{"error": "Failed to delete user"}`)
		return
	}
	ctx.SetStatusCode(fasthttp.StatusNoContent)
}
