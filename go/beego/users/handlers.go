package users

import (
	"strconv"
	// "go.opentelemetry.io/otel/attribute"
	// oteltrace "go.opentelemetry.io/otel/trace"
	beego "github.com/beego/beego/v2/server/web"
)

type UsersHandler struct {
	controller *UsersController
	tracer     interface{} // Replace oteltrace.Tracer with interface{}
}

func NewUsersHandler(c *UsersController, t interface{}) *UsersHandler {
	return &UsersHandler{
		controller: c,
		tracer:     t,
	}
}

// Beego-compatible handlers
func (u *UsersHandler) GetUsersBeego(ctx *beego.Controller) {
	users, err := u.controller.GetUsers(ctx.Ctx.Request.Context())
	if err != nil {
		ctx.Ctx.Output.SetStatus(500)
		ctx.Data["json"] = map[string]string{"error": "Failed to fetch users"}
		ctx.ServeJSON()
		return
	}
	ctx.Data["json"] = users
	ctx.ServeJSON()
}

func (u *UsersHandler) GetUserBeego(ctx *beego.Controller) {
	id := ctx.Ctx.Input.Param(":id")
	user, err := u.controller.GetUser(ctx.Ctx.Request.Context(), id)
	if err != nil {
		ctx.Ctx.Output.SetStatus(404)
		ctx.Data["json"] = map[string]string{"message": "User not found"}
		ctx.ServeJSON()
		return
	}
	ctx.Data["json"] = user
	ctx.ServeJSON()
}

func (u *UsersHandler) CreateUserBeego(ctx *beego.Controller) {
	var newUser User
	if err := ctx.ParseForm(&newUser); err != nil {
		ctx.Ctx.Output.SetStatus(400)
		ctx.Data["json"] = map[string]string{"error": "Invalid input data"}
		ctx.ServeJSON()
		return
	}
	if err := u.controller.CreateUser(ctx.Ctx.Request.Context(), &newUser); err != nil {
		ctx.Ctx.Output.SetStatus(500)
		ctx.Data["json"] = map[string]string{"error": "Failed to create user"}
		ctx.ServeJSON()
		return
	}
	ctx.Ctx.Output.SetStatus(201)
	ctx.Data["json"] = newUser
	ctx.ServeJSON()
}

func (u *UsersHandler) UpdateUserBeego(ctx *beego.Controller) {
	id := ctx.Ctx.Input.Param(":id")
	idInt, err := strconv.Atoi(id)
	if err != nil {
		ctx.Ctx.Output.SetStatus(400)
		ctx.Data["json"] = map[string]string{"message": "Invalid ID"}
		ctx.ServeJSON()
		return
	}
	var updateData struct {
		Name string `json:"name"`
	}
	if err := ctx.ParseForm(&updateData); err != nil {
		ctx.Ctx.Output.SetStatus(400)
		ctx.Data["json"] = map[string]string{"message": "Invalid input data"}
		ctx.ServeJSON()
		return
	}
	user := u.controller.UpdateUser(ctx.Ctx.Request.Context(), idInt, updateData.Name)
	if user == nil {
		ctx.Ctx.Output.SetStatus(404)
		ctx.Data["json"] = map[string]string{"message": "User not found"}
		ctx.ServeJSON()
		return
	}
	ctx.Data["json"] = user
	ctx.ServeJSON()
}

func (u *UsersHandler) DeleteUserBeego(ctx *beego.Controller) {
	id := ctx.Ctx.Input.Param(":id")
	idInt, err := strconv.Atoi(id)
	if err != nil {
		ctx.Ctx.Output.SetStatus(400)
		ctx.Data["json"] = map[string]string{"message": "Invalid ID"}
		ctx.ServeJSON()
		return
	}
	if err := u.controller.DeleteUser(ctx.Ctx.Request.Context(), idInt); err != nil {
		ctx.Ctx.Output.SetStatus(500)
		ctx.Data["json"] = map[string]string{"error": "Failed to delete user"}
		ctx.ServeJSON()
		return
	}
	ctx.Ctx.Output.SetStatus(204)
	ctx.ServeJSON()
}
