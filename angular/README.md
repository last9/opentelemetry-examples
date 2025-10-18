# Last9 Angular Monitoring Sample

This is a comprehensive Angular 20 application that demonstrates how to integrate OpenTelemetry tracing with Last9 for monitoring and observability.


## Quick Start

### 1. Install Dependencies
```bash
npm install
```

### 2. Configure Last9 Authentication
Copy the environment example files and add your Last9 credentials:

```bash
cp src/environments/environment.example.ts src/environments/environment.ts
cp src/environments/environment.prod.example.ts src/environments/environment.prod.ts
```

Then edit the files and replace:
- `YOUR_LAST9_OTLP_ENDPOINT_HERE` with your Last9 OTLP endpoint
- `YOUR_LAST9_TOKEN_HERE` with your Last9 authentication token
- `your-service-name` with your actual service name

**Or use the automated setup script:**
```bash
chmod +x setup.sh
./setup.sh
```

### 3. Start Development Server
```bash
ng serve
```

Navigate to `http://localhost:4200/` to access the application.

## Detailed Setup Instructions

For comprehensive setup instructions with code examples, see:
- **[ANGULAR_SETUP_INSTRUCTIONS.md](./ANGULAR_SETUP_INSTRUCTIONS.md)** - Complete setup guide with TypeScript and JavaScript examples

## Test Scenarios

The application includes 7 comprehensive test scenarios accessible via the UI buttons:

1. **🚀 Run All Tests** - Executes all monitoring scenarios
2. **❌ JS Errors** - JavaScript error scenarios (ReferenceError, TypeError, SyntaxError)
3. **🌐 Network Errors** - Network failure scenarios (404, 500, timeout, CORS)
4. **⚡ Performance** - Performance issue scenarios (slow operations, memory leaks)
5. **👆 UI Issues** - User interaction problems (slow responses, form validation)
6. **🅰️ Angular Issues** - Angular-specific problems (change detection, component errors)
7. **💼 Business Logic** - Business rule violations and data processing errors
8. **✅ Success Tests** - Normal operations and successful API calls

## Configuration

### Environment Variables

The application uses environment-specific configuration files:

- `src/environments/environment.ts` - Development configuration
- `src/environments/environment.prod.ts` - Production configuration

Each file contains:
- `production`: Boolean flag for production mode
- `environment`: Environment name (Dev/Prod)
- `serviceVersion`: Application version (default: 1.0.0)
- `last9.traceEndpoint`: Last9 OTLP endpoint URL
- `last9.authorizationHeader`: Your Last9 authentication token
- `last9.serviceName`: Service identifier for Last9

### OpenTelemetry Packages

The application uses the following OpenTelemetry packages (exact versions for compatibility):
- `@opentelemetry/api@1.9.0`
- `@opentelemetry/auto-instrumentations-web@0.48.1`
- `@opentelemetry/exporter-trace-otlp-http@0.48.0`
- `@opentelemetry/instrumentation@0.48.0`
- `@opentelemetry/resources@1.30.1`
- `@opentelemetry/sdk-trace-web@1.30.1`
- `@opentelemetry/semantic-conventions@1.34.0`

### Last9 Integration

The app automatically sends traces to Last9 with:
- **Service Name**: As configured in environment files
- **Environment**: Dev/Prod based on build configuration
- **Trace Types**: HTTP requests, user interactions, errors, performance metrics

## Monitoring

Check your Last9 dashboard at [https://app.last9.io](https://app.last9.io) to view:
- Real-time traces from the application
- Performance metrics and error rates
- Network request monitoring
