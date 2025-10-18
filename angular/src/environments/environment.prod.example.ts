// Example environment configuration for production
// Copy this file to environment.prod.ts and replace placeholder values

import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';

export const environment = {
  production: true,
  environment: 'Prod',
  serviceVersion: '1.0.0',
  last9: {
    traceEndpoint: 'YOUR_LAST9_OTLP_ENDPOINT_HERE',
    authorizationHeader: 'YOUR_LAST9_TOKEN_HERE',
    serviceName: 'your-service-name'
  }
};

// Example resource configuration (following current OpenTelemetry signature)
const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: environment.last9?.serviceName,
  [SemanticResourceAttributes.SERVICE_VERSION]: environment.serviceVersion,
  [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: environment.environment,
});
