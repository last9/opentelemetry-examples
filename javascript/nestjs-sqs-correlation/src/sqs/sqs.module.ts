import { Module } from "@nestjs/common";
import { SqsPollerService } from "./sqs-poller.service";
import { SqsProducerService } from "./sqs-producer.service";
import { ProcessingModule } from "../processing/processing.module";

@Module({
  imports: [ProcessingModule],
  providers: [SqsPollerService, SqsProducerService],
  exports: [SqsProducerService],
})
export class SqsModule {}
