import { Module } from "@nestjs/common";
import { MessageProcessorService } from "./message-processor.service";

@Module({
  providers: [MessageProcessorService],
  exports: [MessageProcessorService],
})
export class ProcessingModule {}
