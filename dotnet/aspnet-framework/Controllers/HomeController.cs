using System.Net.Http;
using System.Threading.Tasks;
using System.Web.Mvc;
using AspNetFramework.Data;

namespace AspNetFramework.Controllers
{
    /// <summary>
    /// MVC controller — no OTel code.
    /// Demonstrates that both MVC and Web API controllers are instrumented by the same profiler.
    /// </summary>
    public class HomeController : Controller
    {
        private static readonly TodoRepository _repo = new TodoRepository();
        private static readonly HttpClient _http = new HttpClient();

        // GET /
        public ActionResult Index()
        {
            var todos = _repo.GetAll();
            return View(todos);
        }

        // GET /home/upstream
        public async Task<ActionResult> Upstream()
        {
            var json = await _http.GetStringAsync("https://httpbin.org/json");
            return Content(json, "application/json");
        }
    }
}
