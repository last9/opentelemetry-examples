import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { SqsModule } from "./sqs/sqs.module";
import { ProcessingModule } from "./processing/processing.module";

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ProcessingModule,
    SqsModule,
  ],
})
export class AppModule {}
