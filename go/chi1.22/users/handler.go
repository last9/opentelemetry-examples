package users

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
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
	ctx, span := u.tracer.Start(r.Context(), "GetUsers")
	defer span.End()

	users, err := u.controller.GetUsers(ctx)
	if err != nil {
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
		http.Error(w, `{"message": "User not found"}`, http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

func (u *UsersHandler) CreateUser(w http.ResponseWriter, r *http.Request) {
	log.Println("here")
	_, span := u.tracer.Start(r.Context(), "CreateUser")
	defer span.End()

	var newUser User
	if err := json.NewDecoder(r.Body).Decode(&newUser); err != nil {
		http.Error(w, `{"error": "Invalid input data"}`, http.StatusBadRequest)
		return
	}

	err := u.controller.CreateUser(r.Context(), &newUser)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]interface{}{"error": err.Error()})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(nil)
}

func (u *UsersHandler) UpdateUser(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	_, span := u.tracer.Start(r.Context(), "UpdateUser", oteltrace.WithAttributes(
		attribute.String("user.id", id),
	))
	defer span.End()

	idInt, err := strconv.ParseInt(id, 10, 32)
	if err != nil {
		http.Error(w, `{"message": "Invalid ID"}`, http.StatusBadRequest)
		return
	}

	// Parse form data
	err = r.ParseForm()
	if err != nil {
		http.Error(w, `{"message": "Failed to parse form"}`, http.StatusBadRequest)
		return
	}

	name := r.FormValue("name")
	user := u.controller.UpdateUser(int(idInt), name)
	if user == nil {
		http.Error(w, `{"message": "User not found"}`, http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

func (u *UsersHandler) DeleteUser(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	_, span := u.tracer.Start(r.Context(), "DeleteUser", oteltrace.WithAttributes(
		attribute.String("user.id", id),
	))
	defer span.End()

	idInt, err := strconv.ParseInt(id, 10, 32)
	if err != nil {
		http.Error(w, `{"message": "Invalid ID"}`, http.StatusBadRequest)
		return
	}

	err = u.controller.DeleteUser(r.Context(), int(idInt))
	if err != nil {
		http.Error(w, `{"error": "Failed to delete user"}`, http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
