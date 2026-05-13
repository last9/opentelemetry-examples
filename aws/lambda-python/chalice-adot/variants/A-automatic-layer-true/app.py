from chalice import Chalice
import filetype
import aiohttp

app = Chalice(app_name="chalice-adot-a")


@app.route("/")
def index():
    return {
        "filetype_version": filetype.__version__
        if hasattr(filetype, "__version__")
        else "unknown",
        "aiohttp_version": aiohttp.__version__,
    }
