import opentelemetry from '@opentelemetry/api';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import {
  WebTracerProvider,
  ConsoleSpanExporter,
  SimpleSpanProcessor,
  BatchSpanProcessor,
} from '@opentelemetry/sdk-trace-web';
import { getWebAutoInstrumentations } from '@opentelemetry/auto-instrumentations-web';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { Resource } from '@opentelemetry/resources';
import { B3Propagator } from '@opentelemetry/propagator-b3';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';
import { environment } from '../environments/environment';

const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: environment.last9.serviceName,
  [SemanticResourceAttributes.SERVICE_VERSION]: '0.1.0',
  'environment': environment.environment,
});

const provider = new WebTracerProvider({ resource });

provider.addSpanProcessor(new SimpleSpanProcessor(new ConsoleSpanExporter()));

provider.addSpanProcessor(
  new BatchSpanProcessor(
    new OTLPTraceExporter({
      url: environment.last9.traceEndpoint,
      headers: {
        'Authorization': environment.last9.authorizationHeader,
      },
    })
  )
);

provider.register({
  propagator: new B3Propagator(),
});

registerInstrumentations({
  instrumentations: [
    getWebAutoInstrumentations({
      '@opentelemetry/instrumentation-document-load': {},
      '@opentelemetry/instrumentation-user-interaction': {},
      '@opentelemetry/instrumentation-fetch': {
        propagateTraceHeaderCorsUrls: /.+/,
      },
      '@opentelemetry/instrumentation-xml-http-request': {
        propagateTraceHeaderCorsUrls: /.+/,
      },
    }),
  ],
});

// Test function to demonstrate status codes in spans
function testHttpRequest() {
  const tracer = opentelemetry.trace.getTracer('test-tracer');
  
  tracer.startActiveSpan('test-http-request', (span) => {
    // Add environment attribute to the span
    span.setAttribute('environment', environment.environment);
    
    // Simulate an HTTP request
    fetch('https://httpbin.org/status/200')
      .then(response => {
        span.setAttribute('http.status_code', response.status);
        span.setAttribute('http.status_text', response.statusText);
        span.setAttribute('http.url', 'https://httpbin.org/status/200');
        console.log('✅ Test request completed with status:', response.status);
        span.end();
      })
      .catch(error => {
        span.setAttribute('error', true);
        span.setAttribute('error.message', error.message);
        console.error('❌ Test request failed:', error);
        span.end();
      });
  });
}

// Run test after a short delay
setTimeout(testHttpRequest, 2000);
