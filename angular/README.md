# Last9 Angular Monitoring Sample

This is a comprehensive Angular 20 application that demonstrates how to integrate OpenTelemetry tracing with Last9 for monitoring and observability.

## Features

- **OpenTelemetry Integration**: Full OTEL setup with auto-instrumentation
- **Last9 Backend**: Configured to send traces to Last9 observability platform
- **Test Scenarios**: 7 comprehensive test categories for monitoring validation
- **Interactive UI**: Test buttons to generate various types of traces
- **Production Ready**: Clean configuration for development and production

## Quick Start

### 1. Install Dependencies
```bash
npm install
```

### 2. Configure Last9 Authentication
Copy the environment example files and add your Last9 token:

```bash
cp src/environments/environment.example.ts src/environments/environment.ts
cp src/environments/environment.prod.example.ts src/environments/environment.prod.ts
```

Then edit the files and replace `YOUR_LAST9_TOKEN_HERE` with your actual Last9 authentication token.

### 3. Start Development Server
```bash
ng serve
```

Navigate to `http://localhost:4200/` to access the application.

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
- `traceEndpoint`: Last9 OTLP endpoint URL
- `authorizationHeader`: Your Last9 authentication token
- `serviceName`: Service identifier for Last9

### Last9 Integration

The app automatically sends traces to Last9 with:
- **Service Name**: As configured in environment files
- **Environment**: Dev/Prod based on build configuration
- **Trace Types**: HTTP requests, user interactions, errors, performance metrics

## Monitoring

Check your Last9 dashboard at [https://app.last9.io](https://app.last9.io) to view:
- Real-time traces from the application
- Performance metrics and error rates
- User interaction analytics
- Network request monitoring
