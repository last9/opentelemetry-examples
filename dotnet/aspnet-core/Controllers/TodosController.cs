using Microsoft.AspNetCore.Mvc;
using AspNetCore.Data;
using AspNetCore.Models;

namespace AspNetCore.Controllers
{
    /// <summary>
    /// Controller-based Web API — no OTel code.
    /// The CLR profiler auto-instruments:
    ///   - Incoming HTTP requests  → ASP.NET Core span
    ///   - DbCommand.Execute*      → db span (SQLite / SqlClient)
    ///   - HttpClient outbound     → http.client span with W3C traceparent propagation
    /// </summary>
    [ApiController]
    [Route("api/todos")]
    public class TodosController : ControllerBase
    {
        private readonly TodoRepository _repo;
        private readonly IHttpClientFactory _httpFactory;

        public TodosController(TodoRepository repo, IHttpClientFactory httpFactory)
        {
            _repo = repo;
            _httpFactory = httpFactory;
        }

        // GET api/todos
        [HttpGet]
        public async Task<IActionResult> GetAll() =>
            Ok(await _repo.GetAllAsync());

        // POST api/todos
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] Todo todo)
        {
            if (string.IsNullOrWhiteSpace(todo.Title))
                return BadRequest(new { error = "Title is required" });

            var created = await _repo.CreateAsync(todo);
            return CreatedAtAction(nameof(GetAll), created);
        }

        // PATCH api/todos/{id}/complete
        [HttpPatch("{id:int}/complete")]
        public async Task<IActionResult> Complete(int id) =>
            await _repo.CompleteAsync(id) ? Ok() : NotFound();

        // GET api/todos/upstream — outbound HTTP call (auto-instrumented)
        // W3C traceparent header is injected automatically — no code needed.
        [HttpGet("upstream")]
        public async Task<IActionResult> GetUpstream()
        {
            var client = _httpFactory.CreateClient();
            var response = await client.GetAsync("https://httpbin.org/json");
            var body = await response.Content.ReadAsStringAsync();
            return Ok(new
            {
                status  = (int)response.StatusCode,
                preview = body[..Math.Min(200, body.Length)]
            });
        }
    }
}
