using Microsoft.Data.Sqlite;
using AspNetCore.Models;

namespace AspNetCore.Data
{
    /// <summary>
    /// ADO.NET data access layer using SQLite.
    /// OTel auto-instrumentation captures DbCommand.Execute* calls as db spans automatically —
    /// no OTel code required here.
    ///
    /// For SQL Server production use, swap SqliteConnection for SqlConnection
    /// (Microsoft.Data.SqlClient) and update the connection string.
    /// </summary>
    public class TodoRepository
    {
        private readonly string _connectionString;

        public TodoRepository(IConfiguration config)
        {
            _connectionString = config.GetConnectionString("Todos")
                ?? "Data Source=todos.db";
            EnsureSchema();
        }

        private void EnsureSchema()
        {
            using var conn = new SqliteConnection(_connectionString);
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText =
                "CREATE TABLE IF NOT EXISTS todos (" +
                "  id    INTEGER PRIMARY KEY AUTOINCREMENT," +
                "  title TEXT    NOT NULL," +
                "  done  INTEGER NOT NULL DEFAULT 0" +
                ")";
            cmd.ExecuteNonQuery();
        }

        public async Task<List<Todo>> GetAllAsync()
        {
            var todos = new List<Todo>();
            using var conn = new SqliteConnection(_connectionString);
            await conn.OpenAsync();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT id, title, done FROM todos ORDER BY id";
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                todos.Add(new Todo
                {
                    Id    = reader.GetInt32(0),
                    Title = reader.GetString(1),
                    Done  = reader.GetInt32(2) == 1
                });
            }
            return todos;
        }

        public async Task<Todo> CreateAsync(Todo todo)
        {
            using var conn = new SqliteConnection(_connectionString);
            await conn.OpenAsync();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "INSERT INTO todos (title, done) VALUES (@title, @done); SELECT last_insert_rowid()";
            cmd.Parameters.AddWithValue("@title", todo.Title);
            cmd.Parameters.AddWithValue("@done", todo.Done ? 1 : 0);
            todo.Id = Convert.ToInt32(await cmd.ExecuteScalarAsync());
            return todo;
        }

        public async Task<bool> CompleteAsync(int id)
        {
            using var conn = new SqliteConnection(_connectionString);
            await conn.OpenAsync();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "UPDATE todos SET done = 1 WHERE id = @id";
            cmd.Parameters.AddWithValue("@id", id);
            return await cmd.ExecuteNonQueryAsync() > 0;
        }
    }
}
