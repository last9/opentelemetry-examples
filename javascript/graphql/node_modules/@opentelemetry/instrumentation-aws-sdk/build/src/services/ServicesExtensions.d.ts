import { Tracer, Span, DiagLogger, Meter, HrTime } from '@opentelemetry/api';
import { ServiceExtension, RequestMetadata } from './ServiceExtension';
import { AwsSdkInstrumentationConfig, NormalizedRequest, NormalizedResponse } from '../types';
export declare class ServicesExtensions implements ServiceExtension {
    services: Map<string, ServiceExtension>;
    constructor();
    requestPreSpanHook(request: NormalizedRequest, config: AwsSdkInstrumentationConfig, diag: DiagLogger): RequestMetadata;
    requestPostSpanHook(request: NormalizedRequest): void;
    responseHook(response: NormalizedResponse, span: Span, tracer: Tracer, config: AwsSdkInstrumentationConfig, startTime: HrTime): void;
    updateMetricInstruments(meter: Meter): void;
}
//# sourceMappingURL=ServicesExtensions.d.ts.map