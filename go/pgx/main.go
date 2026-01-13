package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"

	"github.com/exaring/otelpgx"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/last9/go-agent"
	ginagent "github.com/last9/go-agent/instrumentation/gin"
)

var conn *pgxpool.Pool

func main() {
	// Initialize go-agent (automatic OpenTelemetry setup)
	agent.Start()
	defer agent.Shutdown()

	log.Println("✓ go-agent initialized")

	var err error
	var connString = os.Getenv("DATABASE_URL")
	if connString == "" {
		connString = "postgres://postgres:postgres@localhost:5432/todos?sslmode=disable"
	}

	cfg, err := pgxpool.ParseConfig(connString)
	if err != nil {
		fmt.Fprintf(os.Stderr, "create connection pool: %v\n", err)
		os.Exit(1)
	}

	// pgxpool uses otelpgx tracer (go-agent provides the tracer provider)
	cfg.ConnConfig.Tracer = otelpgx.NewTracer()
	conn, err = pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Unable to connection to database: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close()

	log.Println("✓ pgxpool connected with OTel tracing")

	// Create Gin router with go-agent instrumentation
	r := ginagent.Default()

	r.GET("/tasks", listTasksHandler)
	r.POST("/tasks", addTaskHandler)
	r.PUT("/tasks/:id", updateTaskHandler)
	r.DELETE("/tasks/:id", removeTaskHandler)

	log.Println("✓ Gin server running on :8080 (instrumented by go-agent)")
	r.Run(":8080")
}

func listTasksHandler(c *gin.Context) {
	tasks, err := listTasks(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, tasks)
}

func addTaskHandler(c *gin.Context) {
	var task struct {
		Description string `json:"description" binding:"required"`
	}
	if err := c.ShouldBindJSON(&task); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	err := addTask(c.Request.Context(), task.Description)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.Status(http.StatusCreated)
}

func updateTaskHandler(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid task ID"})
		return
	}
	var task struct {
		Description string `json:"description" binding:"required"`
	}
	if err := c.ShouldBindJSON(&task); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	err = updateTask(c.Request.Context(), int32(id), task.Description)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.Status(http.StatusOK)
}

func removeTaskHandler(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid task ID"})
		return
	}
	err = removeTask(c.Request.Context(), int32(id))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.Status(http.StatusOK)
}

func listTasks(ctx context.Context) ([]gin.H, error) {
	rows, _ := conn.Query(ctx, "select * from tasks")
	defer rows.Close()

	var tasks []gin.H
	for rows.Next() {
		var id int32
		var description string
		err := rows.Scan(&id, &description)
		if err != nil {
			return nil, err
		}
		tasks = append(tasks, gin.H{"id": id, "description": description})
	}

	return tasks, rows.Err()
}

func addTask(ctx context.Context, description string) error {
	_, err := conn.Exec(ctx, "insert into tasks(description) values($1)", description)
	return err
}

func updateTask(ctx context.Context, itemNum int32, description string) error {
	_, err := conn.Exec(ctx, "update tasks set description=$1 where id=$2", description, itemNum)
	return err
}

func removeTask(ctx context.Context, itemNum int32) error {
	_, err := conn.Exec(ctx, "delete from tasks where id=$1", itemNum)
	return err
}

func printHelp() {
	fmt.Print(`Todo pgx demo

Usage:

  todo list
  todo add task
  todo update task_num item
  todo remove task_num

Example:

  todo add 'Learn Go'
  todo list
`)
}
