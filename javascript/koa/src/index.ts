import { setupTracing } from "./instrumentation";
import * as dotenv from "dotenv";
dotenv.config();
// Do this before requiring koa package
setupTracing("koa-api-server");

import EnvVars from "./common/EnvVars";
import server from "./server";

const SERVER_START_MSG =
  "Koa server started on port: " + EnvVars.Port.toString();

server.listen(EnvVars.Port, () => {
  console.log(SERVER_START_MSG);
});
