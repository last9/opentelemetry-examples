// instrumentation must load before NestJS bootstraps
import "./instrumentation";

import { NestFactory } from "@nestjs/core";
import { AppModule } from "./app.module";
import { OtelLogger } from "./otel-logger";

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    bufferLogs: true,
  });
  app.useLogger(new OtelLogger());
  await app.listen(process.env.PORT ?? 3000);
}

bootstrap();
