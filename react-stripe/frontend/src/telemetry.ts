import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { ZoneContextManager } from '@opentelemetry/context-zone';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { DocumentLoadInstrumentation } from '@opentelemetry/instrumentation-document-load';
import { UserInteractionInstrumentation } from '@opentelemetry/instrumentation-user-interaction';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';
import { trace } from '@opentelemetry/api';
import { LoggerProvider, BatchLogRecordProcessor } from '@opentelemetry/sdk-logs';
import { OTLPLogExporter } from '@opentelemetry/exporter-logs-otlp-http';
import { logs } from '@opentelemetry/api-logs';

const getOrCreateClientId = (): string => {
  const KEY = 'last9_client_id';
  let id = localStorage.getItem(KEY);
  if (!id) {
    id = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
    });
    localStorage.setItem(KEY, id);
  }
  return id;
};

const CONFIG = {
  serviceName: process.env.REACT_APP_OTEL_SERVICE_NAME || 'stripe-checkout',
  tracesEndpoint: process.env.REACT_APP_OTEL_TRACES_ENDPOINT || '',
  logsEndpoint: process.env.REACT_APP_OTEL_LOGS_ENDPOINT || '',
  apiToken: process.env.REACT_APP_OTEL_API_TOKEN || '',
  origin: process.env.REACT_APP_OTEL_ORIGIN || window.location.origin,
  environment: process.env.REACT_APP_OTEL_ENVIRONMENT || 'development',
};

export const setupTelemetry = (): void => {
  if (!CONFIG.tracesEndpoint || !CONFIG.logsEndpoint || !CONFIG.apiToken) {
    console.warn(
      '[OTel] Missing required config. Set REACT_APP_OTEL_TRACES_ENDPOINT, ' +
        'REACT_APP_OTEL_LOGS_ENDPOINT, and REACT_APP_OTEL_API_TOKEN.'
    );
    return;
  }

  const clientId = getOrCreateClientId();

  const resource = resourceFromAttributes({
    [SemanticResourceAttributes.SERVICE_NAME]: CONFIG.serviceName,
    [SemanticResourceAttributes.SERVICE_VERSION]: '1.0.0',
    [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: CONFIG.environment,
  });

  const authHeaders = {
    'X-LAST9-API-TOKEN': `Bearer ${CONFIG.apiToken}`,
    'Client-ID': clientId,
    'X-LAST9-ORIGIN': CONFIG.origin,
  };

  // ── Traces ────────────────────────────────────────────────────────────────
  const traceExporter = new OTLPTraceExporter({
    url: CONFIG.tracesEndpoint,
    headers: authHeaders,
  });

  const tracerProvider = new WebTracerProvider({
    resource,
    spanProcessors: [new BatchSpanProcessor(traceExporter)],
  });

  tracerProvider.register({ contextManager: new ZoneContextManager() });

  registerInstrumentations({
    instrumentations: [
      new DocumentLoadInstrumentation(),
      new FetchInstrumentation({
        propagateTraceHeaderCorsUrls: [/.+/g],
        clearTimingResources: true,
        // Prevent feedback loop: don't trace the OTLP export calls themselves
        ignoreUrls: [/telemetry\/client_monitoring/],
      }),
      new UserInteractionInstrumentation({ eventNames: ['click', 'submit'] }),
    ],
  });

  // ── Logs ──────────────────────────────────────────────────────────────────
  const logExporter = new OTLPLogExporter({
    url: CONFIG.logsEndpoint,
    headers: authHeaders,
  });

  const loggerProvider = new LoggerProvider({ resource });
  loggerProvider.addLogRecordProcessor(new BatchLogRecordProcessor(logExporter));
  logs.setGlobalLoggerProvider(loggerProvider);
};

export const getTracer = () => trace.getTracer('stripe-payments', '1.0.0');
export const getLogger = () => logs.getLogger('stripe-payments', '1.0.0');
