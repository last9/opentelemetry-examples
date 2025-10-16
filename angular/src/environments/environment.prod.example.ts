// Example environment configuration for production
// Copy this file to environment.prod.ts and replace with your actual values

export const environment = {
  production: true,
  environment: 'Prod',
  last9: {
    // Replace YOUR_OTLP_ENDPOINT with your actual Last9 OTLP endpoint
    traceEndpoint: 'YOUR_OTLP_ENDPOINT',
    // Replace with your actual Last9 authentication token
    authorizationHeader: 'Bearer YOUR_LAST9_TOKEN_HERE',
    serviceName: 'your-service-name'
  }
};
