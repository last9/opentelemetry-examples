import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { ZoneContextManager } from '@opentelemetry/context-zone';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { DocumentLoadInstrumentation } from '@opentelemetry/instrumentation-document-load';
import { UserInteractionInstrumentation } from '@opentelemetry/instrumentation-user-interaction';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { resourceFromAttributes } from '@opentelemetry/resources';
import {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION
} from '@opentelemetry/semantic-conventions/incubating';
import { SEMRESATTRS_DEPLOYMENT_ENVIRONMENT } from '@opentelemetry/semantic-conventions';
import { trace, context, SpanStatusCode, Span } from '@opentelemetry/api';

// Generate or retrieve browser fingerprint (Client-ID)
const getClientId = (): string => {
  const STORAGE_KEY = 'last9_client_id';
  let clientId = localStorage.getItem(STORAGE_KEY);

  if (!clientId) {
    // Generate a simple UUID-like identifier
    clientId = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : ((r & 0x3) | 0x8);
      return v.toString(16);
    });
    localStorage.setItem(STORAGE_KEY, clientId);
  }

  return clientId;
};

// Configuration from environment variables or window object
// For Angular, we'll inject these from environment.ts or use window object
declare global {
  interface Window {
    __OTEL_CONFIG__?: {
      serviceName?: string;
      endpoint?: string;
      apiToken?: string;
      origin?: string;
      environment?: string;
    };
  }
}

export const setupTelemetry = () => {
  console.log('🚀 Initializing OpenTelemetry for Angular App...');

  // Read configuration from window object (set by main.ts)
  const OTEL_CONFIG = {
    serviceName: window.__OTEL_CONFIG__?.serviceName || 'angular-app',
    endpoint: window.__OTEL_CONFIG__?.endpoint || '',
    apiToken: window.__OTEL_CONFIG__?.apiToken || '',
    origin: window.__OTEL_CONFIG__?.origin || window.location.origin,
    environment: window.__OTEL_CONFIG__?.environment || 'development'
  };

  // Validate required configuration
  if (!OTEL_CONFIG.serviceName || !OTEL_CONFIG.endpoint || !OTEL_CONFIG.apiToken) {
    console.error('❌ Missing required OpenTelemetry configuration');
    console.error('   Required: serviceName, endpoint, apiToken');
    console.error('   Please configure window.__OTEL_CONFIG__ before calling setupTelemetry()');
    return;
  }

  // Create resource with service information
  const resource = resourceFromAttributes({
    [ATTR_SERVICE_NAME]: OTEL_CONFIG.serviceName,
    [ATTR_SERVICE_VERSION]: '1.0.0',
    [SEMRESATTRS_DEPLOYMENT_ENVIRONMENT]: OTEL_CONFIG.environment,
  });

  // Get or generate Client-ID (browser fingerprint)
  const clientId = getClientId();

  // Configure OTLP exporter with Last9 Client Monitoring headers
  const otlpExporter = new OTLPTraceExporter({
    url: OTEL_CONFIG.endpoint,
    headers: {
      'X-LAST9-API-TOKEN': `Bearer ${OTEL_CONFIG.apiToken}`,
      'Client-ID': clientId,
      'X-LAST9-ORIGIN': OTEL_CONFIG.origin,
    },
  });

  // Add span processor
  const spanProcessor = new BatchSpanProcessor(otlpExporter, {
    maxExportBatchSize: 512,
    exportTimeoutMillis: 30000,
    scheduledDelayMillis: 5000,
  });

  // Create tracer provider with span processor
  const provider = new WebTracerProvider({
    resource,
    spanProcessors: [spanProcessor],
  });

  // Register the provider with Zone context manager for async operations
  // Angular already uses Zone.js, so this will work seamlessly
  provider.register({
    contextManager: new ZoneContextManager(),
  });

  // Register auto-instrumentations
  registerInstrumentations({
    instrumentations: [
      // Document load instrumentation - captures page load events
      new DocumentLoadInstrumentation({
        enabled: true,
      }),

      // Fetch instrumentation - captures HTTP requests
      new FetchInstrumentation({
        enabled: true,
        // Propagate trace headers to all URLs for end-to-end tracing
        propagateTraceHeaderCorsUrls: [/.+/g],
        // Clear timing resources to avoid memory leaks
        clearTimingResources: true,
        // Ignore requests to OTLP endpoint to prevent interference
        ignoreUrls: [/otlp-aps1\.last9\.io/],
      }),

      // User interaction instrumentation - captures button clicks, form submissions, etc.
      new UserInteractionInstrumentation({
        enabled: true,
        // Capture events on these DOM elements
        eventNames: ['click', 'submit'],
        // Add element details to spans for better debugging
        shouldPreventSpanCreation: (_eventType, _element) => {
          // Don't create spans for trivial interactions
          // You can customize this based on your needs
          return false;
        },
      }),
    ],
  });

  console.log('✅ OpenTelemetry initialized successfully!');
  console.log(`📊 Service: ${OTEL_CONFIG.serviceName}`);
  console.log(`🌍 Environment: ${OTEL_CONFIG.environment}`);

  return provider;
};

// Export the setup function
export default setupTelemetry;

// ============================================================================
// Custom Span Utilities
// ============================================================================

// Get a tracer for custom user action spans
const getUserActionsTracer = () => {
  return trace.getTracer('user-actions', '1.0.0');
};

/**
 * Creates a custom span for tracking user actions
 * @param name - Name of the action (e.g., "user.login", "user.search")
 * @param attributes - Additional attributes to add to the span
 * @param fn - Async function to execute within the span
 * @returns Promise<T> - Result of the function
 */
export const traceUserAction = async <T>(
  name: string,
  attributes: Record<string, string | number | boolean>,
  fn: () => Promise<T>
): Promise<T> => {
  const tracer = getUserActionsTracer();
  const span = tracer.startSpan(name);

  // Add attributes to the span
  Object.entries(attributes).forEach(([key, value]) => {
    span.setAttribute(key, value);
  });

  try {
    // Execute the function within the span context
    const result = await context.with(trace.setSpan(context.active(), span), fn);

    // Mark span as successful
    span.setStatus({ code: SpanStatusCode.OK });
    return result;
  } catch (error) {
    // Mark span as failed and record error
    span.setStatus({
      code: SpanStatusCode.ERROR,
      message: error instanceof Error ? error.message : String(error),
    });
    span.recordException(error as Error);
    throw error;
  } finally {
    // Always end the span
    span.end();
  }
};

/**
 * Creates a custom span without async execution
 * Returns the span object so you can end it manually
 * @param name - Name of the action
 * @param attributes - Additional attributes
 * @returns Span object
 */
export const startCustomSpan = (
  name: string,
  attributes?: Record<string, string | number | boolean>
): Span => {
  const tracer = getUserActionsTracer();
  const span = tracer.startSpan(name);

  if (attributes) {
    Object.entries(attributes).forEach(([key, value]) => {
      span.setAttribute(key, value);
    });
  }

  return span;
};
