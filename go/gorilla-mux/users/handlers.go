package users

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/gorilla/mux"
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

func (u *UsersHandler) GetUsers(w http.ResponseWriter, r *http.Request) {
	traceCtx, span := u.tracer.Start(r.Context(), "GetUsers")
	defer span.End()

	users, err := u.controller.GetUsers(traceCtx)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "Failed to fetch users"})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(users)
}

func (u *UsersHandler) GetUser(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]
	traceCtx, span := u.tracer.Start(r.Context(), "GetUser", oteltrace.WithAttributes(
		attribute.String("user.id", id),
	))
	defer span.End()

	user, err := u.controller.GetUser(traceCtx, id)
	if err != nil {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"message": "User not found"})
		return
	}
	json.NewEncoder(w).Encode(user)
}

func (u *UsersHandler) CreateUser(w http.ResponseWriter, r *http.Request) {
	traceCtx, span := u.tracer.Start(r.Context(), "CreateUser")
	defer span.End()

	var newUser User
	if err := json.NewDecoder(r.Body).Decode(&newUser); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "Invalid input data"})
		return
	}

	err := u.controller.CreateUser(traceCtx, &newUser)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "Failed to create user"})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(newUser)
}

func (u *UsersHandler) UpdateUser(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]
	traceCtx, span := u.tracer.Start(r.Context(), "UpdateUser", oteltrace.WithAttributes(
		attribute.String("user.id", id),
	))
	defer span.End()

	idInt, err := strconv.ParseInt(id, 10, 32)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"message": "Invalid ID"})
		return
	}

	var updateData struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&updateData); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"message": "Invalid input data"})
		return
	}

	user := u.controller.UpdateUser(traceCtx, int(idInt), updateData.Name)
	if user == nil {
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"message": "User not found"})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

func (u *UsersHandler) DeleteUser(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]
	traceCtx, span := u.tracer.Start(r.Context(), "DeleteUser", oteltrace.WithAttributes(
		attribute.String("user.id", id),
	))
	defer span.End()

	idInt, err := strconv.ParseInt(id, 10, 32)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"message": "Invalid ID"})
		return
	}

	err = u.controller.DeleteUser(traceCtx, int(idInt))
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"error": "Failed to delete user"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
