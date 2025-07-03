import { InstrumentationBase } from '@opentelemetry/instrumentation';

/**
 * Instruments a Polka app to auto-create OpenTelemetry spans for each request.
 * @param app The Polka app instance
 * @param options Options for instrumentation
 */
export declare class PolkaInstrumentation extends InstrumentationBase {
  constructor(config?: object);
  patchApp(app: any, options?: { serviceName?: string }): void;
} 