using System;
using System.Collections.Generic;
using System.Data.SQLite;
using System.IO;
using AspNetFramework.Models;

namespace AspNetFramework.Data
{
    /// <summary>
    /// ADO.NET data access layer using SQLite.
    /// OTel auto-instrumentation captures DbCommand.Execute* calls as db spans automatically —
    /// no OTel code required here.
    ///
    /// For SQL Server production use, swap SQLiteConnection for SqlConnection
    /// (Microsoft.Data.SqlClient) and update the connection string.
    /// </summary>
    public class TodoRepository
    {
        private readonly string _connectionString;

        public TodoRepository()
        {
            var dbPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "App_Data", "todos.db");
            Directory.CreateDirectory(Path.GetDirectoryName(dbPath));
            _connectionString = $"Data Source={dbPath};Version=3;";
            EnsureSchema();
        }

        private void EnsureSchema()
        {
            using (var conn = new SQLiteConnection(_connectionString))
            {
                conn.Open();
                using (var cmd = conn.CreateCommand())
                {
                    cmd.CommandText =
                        "CREATE TABLE IF NOT EXISTS todos (" +
                        "  id    INTEGER PRIMARY KEY AUTOINCREMENT," +
                        "  title TEXT    NOT NULL," +
                        "  done  INTEGER NOT NULL DEFAULT 0" +
                        ")";
                    cmd.ExecuteNonQuery();
                }
            }
        }

        public List<Todo> GetAll()
        {
            var todos = new List<Todo>();
            using (var conn = new SQLiteConnection(_connectionString))
            {
                conn.Open();
                using (var cmd = conn.CreateCommand())
                {
                    cmd.CommandText = "SELECT id, title, done FROM todos ORDER BY id";
                    using (var reader = cmd.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            todos.Add(new Todo
                            {
                                Id    = reader.GetInt32(0),
                                Title = reader.GetString(1),
                                Done  = reader.GetInt32(2) == 1
                            });
                        }
                    }
                }
            }
            return todos;
        }

        public int Create(Todo todo)
        {
            using (var conn = new SQLiteConnection(_connectionString))
            {
                conn.Open();
                using (var cmd = conn.CreateCommand())
                {
                    cmd.CommandText = "INSERT INTO todos (title, done) VALUES (@title, @done); SELECT last_insert_rowid()";
                    cmd.Parameters.AddWithValue("@title", todo.Title);
                    cmd.Parameters.AddWithValue("@done", todo.Done ? 1 : 0);
                    var id = Convert.ToInt32(cmd.ExecuteScalar());
                    todo.Id = id;
                    return id;
                }
            }
        }

        public bool Complete(int id)
        {
            using (var conn = new SQLiteConnection(_connectionString))
            {
                conn.Open();
                using (var cmd = conn.CreateCommand())
                {
                    cmd.CommandText = "UPDATE todos SET done = 1 WHERE id = @id";
                    cmd.Parameters.AddWithValue("@id", id);
                    return cmd.ExecuteNonQuery() > 0;
                }
            }
        }
    }
}
