using System;
using System.Net.Http;
using System.Threading.Tasks;
using System.Web.Http;
using AspNetFramework.Data;
using AspNetFramework.Models;

namespace AspNetFramework.Controllers
{
    /// <summary>
    /// Web API controller — no OTel code.
    /// The CLR profiler auto-instruments:
    ///   - Incoming HTTP requests  → ASP.NET span
    ///   - DbCommand.Execute*      → db span (SQLite / SqlClient)
    ///   - HttpClient outbound     → http.client span with W3C traceparent propagation
    /// </summary>
    [RoutePrefix("api/todos")]
    public class TodosController : ApiController
    {
        private static readonly TodoRepository _repo = new TodoRepository();
        private static readonly HttpClient _http = new HttpClient();

        // GET api/todos
        [HttpGet, Route("")]
        public IHttpActionResult GetAll()
        {
            return Ok(_repo.GetAll());
        }

        // POST api/todos
        [HttpPost, Route("")]
        public IHttpActionResult Create([FromBody] Todo todo)
        {
            if (todo == null || string.IsNullOrWhiteSpace(todo.Title))
                return BadRequest("Title is required");

            _repo.Create(todo);
            return Ok(todo);
        }

        // PATCH api/todos/{id}/complete
        [HttpPatch, Route("{id:int}/complete")]
        public IHttpActionResult Complete(int id)
        {
            return _repo.Complete(id) ? (IHttpActionResult)Ok() : NotFound();
        }

        // GET api/todos/upstream — outbound HTTP call (auto-instrumented)
        // W3C traceparent header is injected automatically — no code needed.
        [HttpGet, Route("upstream")]
        public async Task<IHttpActionResult> GetUpstream()
        {
            var response = await _http.GetAsync("https://httpbin.org/json");
            var body = await response.Content.ReadAsStringAsync();
            return Ok(new
            {
                status  = (int)response.StatusCode,
                preview = body.Substring(0, Math.Min(200, body.Length))
            });
        }
    }
}
