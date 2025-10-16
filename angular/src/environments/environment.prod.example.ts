// Example environment configuration for production
// Copy this file to environment.prod.ts and replace with your actual values

export const environment = {
  production: true,
  environment: 'Prod',
  last9: {
    traceEndpoint: 'https://otlp-aps1.last9.io:443/v1/traces',
    // Replace with your actual Last9 authentication token
    authorizationHeader: 'Bearer YOUR_LAST9_TOKEN_HERE',
    serviceName: 'your-service-name'
  }
};
