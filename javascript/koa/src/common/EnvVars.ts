// src/common/EnvVars.ts
import * as dotenv from "dotenv";
dotenv.config();

export default {
  NodeEnv: process.env.NODE_ENV ?? "",
  Port: Number(process.env.PORT ?? 3000),
};
