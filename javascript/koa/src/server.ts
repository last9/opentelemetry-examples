import Koa from "koa";
import Router from "koa-router";
import bodyParser from "koa-bodyparser";
import logger from "koa-logger";
import serve from "koa-static";
import path from "path";
import EnvVars from "./common/EnvVars";
import { NodeEnvs } from "./common/misc";
import HttpStatusCodes from "./common/HttpStatusCodes";

const app = new Koa();
const router = new Router();

// Basic middleware
app.use(bodyParser());

// Show routes called in console during development
if (EnvVars.NodeEnv === NodeEnvs.Dev.valueOf()) {
  app.use(logger());
}

// Error handling middleware
app.use(async (ctx, next) => {
  try {
    await next();
  } catch (err: any) {
    console.error(err);
    ctx.status = err.status || HttpStatusCodes.INTERNAL_SERVER_ERROR;
    ctx.body = { error: err.message };
  }
});

// Routes
router.get("/", (ctx) => {
  ctx.redirect("/users");
});

router.get("/users", (ctx) => {
  ctx.type = "html";
  ctx.body = "<h1>Users Page</h1>";
});

// Use router middleware
app.use(router.routes()).use(router.allowedMethods());

// Serve static files
const staticDir = path.join(__dirname, "..", "public");
app.use(serve(staticDir));

export default app;
