import { Hono } from "hono";
import { Database } from "bun:sqlite";
import { logger } from "hono/logger";

import { setupOTel } from "./otelSetup";
import { otelMiddleware } from "./otelMiddleware";

// Setup OpenTelemetry SDKs
setupOTel();

const app = new Hono();

// Apply the Otel middleware to all routes
app.use("*", otelMiddleware());

const db = new Database("tasks.sqlite");

// Initialize the database
db.run(`
  CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    completed BOOLEAN NOT NULL DEFAULT 0
  )
`);

// GET all tasks
app.get("/tasks", (c) => {
  const tasks = db.query("SELECT * FROM tasks").all();
  return c.json(tasks);
});

// GET a single task
app.get("/tasks/:id", (c) => {
  const id = c.req.param("id");
  const task = db.query("SELECT * FROM tasks WHERE id = ?").get(id);
  if (!task) {
    return c.json({ error: "Task not found" }, 404);
  }
  return c.json(task);
});

// POST a new task
app.post("/tasks", async (c) => {
  const { title } = await c.req.json();
  const result = db.run("INSERT INTO tasks (title) VALUES (?)", title);
  return c.json({ id: result.lastInsertId, title, completed: false }, 201);
});

// PUT (update) a task
app.put("/tasks/:id", async (c) => {
  const id = c.req.param("id");
  const { title, completed } = await c.req.json();
  const result = db.run(
    "UPDATE tasks SET title = ?, completed = ? WHERE id = ?",
    [title, completed ? 1 : 0, id],
  );
  if (result.changes === 0) {
    return c.json({ error: "Task not found" }, 404);
  }
  return c.json({ id, title, completed });
});

// DELETE a task
app.delete("/tasks/:id", (c) => {
  const id = c.req.param("id");
  const result = db.run("DELETE FROM tasks WHERE id = ?", id);
  if (result.changes === 0) {
    return c.json({ error: "Task not found" }, 404);
  }
  return c.json({ message: "Task deleted successfully" });
});

export default app;
