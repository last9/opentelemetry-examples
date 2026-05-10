// Example: GORM v2 instrumented with the official
// gorm.io/plugin/opentelemetry tracing plugin, layered on top of the
// last9/go-agent integrations/database SQL wrapper.
//
// Each HTTP request that hits a handler issues GORM operations and produces
// a two-layer trace:
//
//	gin handler span
//	  └─ select users / insert users / ...   (gorm.io/plugin/opentelemetry)
//	        └─ postgres.query                 (integrations/database / otelsql)
//
// last9/go-agent does not ship a GORM wrapper; the upstream plugin is the
// recommended path. See the README in this directory for the rationale.
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	agent "github.com/last9/go-agent"
	"github.com/last9/go-agent/integrations/database"
	ginagent "github.com/last9/go-agent/instrumentation/gin"
	_ "github.com/lib/pq" // register the "postgres" driver for database.Open
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/plugin/opentelemetry/tracing"
)

type User struct {
	CreatedAt time.Time
	Name      string
	Email     string
	ID        uint `gorm:"primarykey"`
}

func main() {
	agent.Start()
	defer agent.Shutdown()
	log.Println("✓ go-agent initialized")

	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://postgres:postgres@localhost:5432/users?sslmode=disable"
	}

	// Layer 1: SQL driver instrumentation. Produces postgres.query spans.
	sqlDB, err := database.Open(database.Config{
		DriverName:   "postgres",
		DSN:          dsn,
		DatabaseName: "users",
	})
	if err != nil {
		log.Fatalf("open sql: %v", err)
	}
	defer sqlDB.Close()
	log.Println("✓ otelsql wrapper opened")

	// Layer 2: official GORM tracing plugin. Produces "select users",
	// "insert users", etc. as the parent span, with the postgres.query span
	// from integrations/database beneath it.
	db, err := gorm.Open(postgres.New(postgres.Config{Conn: sqlDB}), &gorm.Config{})
	if err != nil {
		log.Fatalf("gorm open: %v", err)
	}
	if err := db.Use(tracing.NewPlugin()); err != nil {
		log.Fatalf("install tracing plugin: %v", err)
	}
	log.Println("✓ gorm.io/plugin/opentelemetry installed")

	if err := db.AutoMigrate(&User{}); err != nil {
		log.Fatalf("automigrate: %v", err)
	}

	r := ginagent.Default()
	r.GET("/users", listUsersHandler(db))
	r.POST("/users", createUserHandler(db))
	r.GET("/users/:id", getUserHandler(db))
	r.PUT("/users/:id", updateUserHandler(db))
	r.DELETE("/users/:id", deleteUserHandler(db))
	r.GET("/users/slow", slowQueryHandler(db))

	addr := ":" + cmpEnv("PORT", "8080")
	srv := &http.Server{
		Addr:              addr,
		Handler:           r,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		log.Printf("✓ Gin running on %s", addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("gin: %v", err)
		}
	}()

	// Shut down on SIGINT/SIGTERM. Defers do not run when the process is
	// killed by a signal, so we install a handler that drains the HTTP
	// server and lets the deferred agent.Shutdown flush spans.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
	log.Println("shutdown: draining server")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("shutdown: %v", err)
	}
	log.Println("shutdown: complete")
}

func cmpEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func listUsersHandler(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		var users []User
		if err := db.WithContext(c.Request.Context()).Find(&users).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, users)
	}
}

func createUserHandler(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		var u User
		if err := c.ShouldBindJSON(&u); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		if err := db.WithContext(c.Request.Context()).Create(&u).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusCreated, u)
	}
}

func getUserHandler(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, err := strconv.Atoi(c.Param("id"))
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "bad id"})
			return
		}
		var u User
		err = db.WithContext(c.Request.Context()).First(&u, id).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, u)
	}
}

func updateUserHandler(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, err := strconv.Atoi(c.Param("id"))
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "bad id"})
			return
		}
		var patch User
		if err := c.ShouldBindJSON(&patch); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		res := db.WithContext(c.Request.Context()).Model(&User{}).Where("id = ?", id).Updates(patch)
		if res.Error != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
			return
		}
		if res.RowsAffected == 0 {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"updated": res.RowsAffected})
	}
}

func deleteUserHandler(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, err := strconv.Atoi(c.Param("id"))
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "bad id"})
			return
		}
		res := db.WithContext(c.Request.Context()).Delete(&User{}, id)
		if res.Error != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"deleted": res.RowsAffected})
	}
}

// slowQueryHandler runs pg_sleep(0.5) so a slow query is observable in the
// trace UI by span duration. We use Exec because pg_sleep returns void.
func slowQueryHandler(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		if err := db.WithContext(c.Request.Context()).Exec("SELECT pg_sleep(0.5)").Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"ok": true})
	}
}
