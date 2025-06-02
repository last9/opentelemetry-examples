package users

import (
	"strconv"
	// "go.opentelemetry.io/otel/attribute"
	// oteltrace "go.opentelemetry.io/otel/trace"
	"beego_example/last9"

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
	last9.WrapBeegoHandler("beego-app", u.getUsersBeegoInner)(ctx)
}

func (u *UsersHandler) getUsersBeegoInner(ctx *beego.Controller) {
	users, err := u.controller.GetUsers(ctx.Ctx.Request.Context())
	if err != nil {
		ctx.Ctx.Output.SetStatus(500)
		ctx.Data["json"] = map[string]string{"error": "Failed to fetch users"}
		ctx.ServeJSON()
		return
	}
	ctx.Ctx.Output.SetStatus(200)
	ctx.Data["json"] = users
	ctx.ServeJSON()
}

func (u *UsersHandler) GetUserBeego(ctx *beego.Controller) {
	last9.WrapBeegoHandler("beego-app", u.getUserBeegoInner)(ctx)
}

func (u *UsersHandler) getUserBeegoInner(ctx *beego.Controller) {
	id := ctx.Ctx.Input.Param(":id")
	user, err := u.controller.GetUser(ctx.Ctx.Request.Context(), id)
	if err != nil {
		ctx.Ctx.Output.SetStatus(404)
		ctx.Data["json"] = map[string]string{"message": "User not found"}
		ctx.ServeJSON()
		return
	}
	ctx.Ctx.Output.SetStatus(200)
	ctx.Data["json"] = user
	ctx.ServeJSON()
}

func (u *UsersHandler) CreateUserBeego(ctx *beego.Controller) {
	last9.WrapBeegoHandler("beego-app", u.createUserBeegoInner)(ctx)
}

func (u *UsersHandler) createUserBeegoInner(ctx *beego.Controller) {
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
	last9.WrapBeegoHandler("beego-app", u.updateUserBeegoInner)(ctx)
}

func (u *UsersHandler) updateUserBeegoInner(ctx *beego.Controller) {
	idStr := ctx.Ctx.Input.Param(":id")
	name := ctx.GetString("name")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		ctx.Ctx.Output.SetStatus(400)
		ctx.Data["json"] = map[string]string{"error": "Invalid user ID"}
		ctx.ServeJSON()
		return
	}
	user := u.controller.UpdateUser(ctx.Ctx.Request.Context(), id, name)
	if user == nil {
		ctx.Ctx.Output.SetStatus(404)
		ctx.Data["json"] = map[string]string{"error": "User not found or update failed"}
		ctx.ServeJSON()
		return
	}
	ctx.Ctx.Output.SetStatus(200)
	ctx.Data["json"] = user
	ctx.ServeJSON()
}

func (u *UsersHandler) DeleteUserBeego(ctx *beego.Controller) {
	last9.WrapBeegoHandler("beego-app", u.deleteUserBeegoInner)(ctx)
}

func (u *UsersHandler) deleteUserBeegoInner(ctx *beego.Controller) {
	id := ctx.Ctx.Input.Param(":id")
	user, err := u.controller.GetUser(ctx.Ctx.Request.Context(), id)
	if err != nil || user == nil {
		ctx.Ctx.Output.SetStatus(404)
		ctx.Data["json"] = map[string]string{"error": "User not found"}
		ctx.ServeJSON()
		return
	}
	// Here you would delete the user from DB and cache (not implemented)
	ctx.Ctx.Output.SetStatus(204)
	ctx.Data["json"] = map[string]string{"message": "User deleted (not really)"}
	ctx.ServeJSON()
}
