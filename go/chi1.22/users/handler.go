package users

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
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

func (u *UsersHandler) GetUsers(w http.ResponseWriter, r *http.Request) {
	ctx, span := u.tracer.Start(r.Context(), "GetUsers")
	defer span.End()

	users, err := u.controller.GetUsers(ctx)
	if err != nil {
        span.SetStatus(codes.Error, err.Error())
		http.Error(w, `{"error": "Failed to fetch users"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(users)
}

func (u *UsersHandler) GetUser(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	_, span := u.tracer.Start(r.Context(), "GetUser", oteltrace.WithAttributes(
		attribute.String("user.id", id),
	))
	defer span.End()

	user, err := u.controller.GetUser(r.Context(), id)
	if err != nil {
        span.SetStatus(codes.Error, err.Error())
		http.Error(w, `{"message": "User not found"}`, http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

func (u *UsersHandler) CreateUser(w http.ResponseWriter, r *http.Request) {
	_, span := u.tracer.Start(r.Context(), "CreateUser")
	defer span.End()

	var newUser User
	if err := json.NewDecoder(r.Body).Decode(&newUser); err != nil {
        span.SetStatus(codes.Error, err.Error())
		http.Error(w, `{"error": "Invalid input data"}`, http.StatusBadRequest)
		return
	}

	err := u.controller.CreateUser(r.Context(), &newUser)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
        span.SetStatus(codes.Error, err.Error())
		json.NewEncoder(w).Encode(map[string]interface{}{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{"message": "User created successfully", "user": newUser})
}

func (u *UsersHandler) UpdateUser(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	_, span := u.tracer.Start(r.Context(), "UpdateUser", oteltrace.WithAttributes(
		attribute.String("user.id", id),
	))
	defer span.End()

	var payload struct {
		Name  *string `json:"name"`
		Email *string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		span.SetStatus(codes.Error, err.Error())
		http.Error(w, `{"message": "Invalid input data"}`, http.StatusBadRequest)
		return
	}

	updated, err := u.controller.UpdateUser(r.Context(), id, payload.Name, payload.Email)
	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		http.Error(w, `{"message": "User not found"}`, http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(updated)
}

func (u *UsersHandler) DeleteUser(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	_, span := u.tracer.Start(r.Context(), "DeleteUser", oteltrace.WithAttributes(
		attribute.String("user.id", id),
	))
	defer span.End()

	if err := u.controller.DeleteUser(r.Context(), id); err != nil {
		span.SetStatus(codes.Error, err.Error())
		http.Error(w, `{"error": "Failed to delete user"}`, http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
