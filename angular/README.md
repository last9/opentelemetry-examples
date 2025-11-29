# Angular OpenTelemetry Demo App - Last9 Integration

A complete reference example showing how to instrument an Angular application with OpenTelemetry and send telemetry data to Last9. This demo includes automatic instrumentation for page loads, HTTP requests, and user interactions.

## 🎯 What This Demo Includes

- ✅ **Auto-instrumented page loads** - Capture page performance metrics
- ✅ **Auto-instrumented HTTP requests** - Track all fetch/XHR calls
- ✅ **Auto-instrumented user interactions** - Monitor button clicks and form submissions
- ✅ **Custom span examples** - Track specific business operations
- ✅ **Distributed tracing ready** - Propagate trace context to backends
- ✅ **Production-ready configuration** - Secure token handling and environment separation

## 📋 Prerequisites

- Node.js 18+ and npm
- Angular CLI 18+ (installed globally via `npm install -g @angular/cli`)
- A Last9 account with access to Client Monitoring tokens
- Basic knowledge of Angular and OpenTelemetry concepts

## 🚀 Quick Start

### Step 1: Install Dependencies

```bash
npm install
```

This will install all required OpenTelemetry packages:
- `@opentelemetry/api` - Core OpenTelemetry API
- `@opentelemetry/sdk-trace-web` - Browser tracing SDK
- `@opentelemetry/instrumentation-fetch` - Auto-instrument HTTP requests
- `@opentelemetry/instrumentation-document-load` - Auto-instrument page loads
- `@opentelemetry/instrumentation-user-interaction` - Auto-instrument clicks/forms
- And other required dependencies

### Step 2: Get Your Last9 Configuration

#### RUM Endpoint URL

The Last9 endpoint URL follows this format:

```
<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces
```

**Where to find these values:**
- `<your-base-url>` - Your Last9 region-specific base endpoint URL
- `<your-org-slug>` - Your organization slug from Last9 dashboard

#### Authentication - Client Token

Create a client token for browser applications:

1. Navigate to [Ingestion Tokens](https://app.last9.io/control-plane/ingestion-tokens) in Last9 dashboard
2. Click **Create New Token** → Select **Client Token**
3. Set the allowed origin to `http://localhost:4200` (for local development)
4. Copy the generated token

**Important**: Use Client Tokens for browser apps, NOT backend authorization tokens!

**Additional Resources:**
- [Getting Started with RUM](https://last9.io/docs/rum-getting-started/)

### Step 3: Configure Environment Variables

Edit the environment configuration files:

**For Development** - `src/environment.ts`:

```typescript
export const environment = {
  production: false,
  otel: {
    serviceName: 'angular-demo-app',
    // Last9 OTLP endpoint for your organization
    // Format: <your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces
    endpoint: '<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces',
    // Your Client Token (from Ingestion Tokens page)
    apiToken: 'your-client-token-here',
    // Allowed origin (must match token configuration)
    origin: 'http://localhost:4200',
    // Environment identifier
    environment: 'development'
  }
};
```

**Replace**:
- In `endpoint`: Replace `<your-base-url>` and `<your-org-slug>` with your actual values
- In `apiToken`: Your client token from Ingestion Tokens page

**For Production** - `src/environment.prod.ts`:

```typescript
export const environment = {
  production: true,
  otel: {
    serviceName: 'angular-demo-app',
    endpoint: '<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces',
    apiToken: 'your-production-client-token-here',
    origin: 'https://yourdomain.com',
    environment: 'production'
  }
};
```

**Important**:
- Create separate client tokens for dev and production with different origin restrictions!
- Never commit tokens to version control

### Step 4: Start the Application

```bash
npm start
# or
ng serve
```

The app will open at `http://localhost:4200` and automatically start sending telemetry to Last9.

### Step 5: Verify Telemetry

**In Browser Console:**

You should see initialization messages:
```
🚀 Initializing OpenTelemetry for Angular Demo App...
✅ OpenTelemetry initialized successfully!
📊 Service: angular-demo-app
🌍 Environment: development
```

When you interact with the app:
```
📤 Exporting 3 span(s) to Last9...
   [1] documentLoad (0) - OK
   [2] HTTP GET (2) - OK
   [3] click (0) - OK
✅ Successfully exported spans to Last9
```

**In Last9 Dashboard:**

Navigate to your Last9 traces dashboard. You should see:
- Traces from service: `angular-demo-app`
- Different span types: `documentLoad`, `HTTP GET`, `click`, `user.*`

## 🧪 Testing Different Features

### Test 1: Page Load Tracing

1. Refresh the page (`Ctrl+R` or `Cmd+R`)
2. Check Last9 for a `documentLoad` span
3. Span attributes include: page load time, resource timing

### Test 2: HTTP Request Tracing

1. Click **"External Users"** or **"External Posts"** buttons
2. Check Last9 for `HTTP GET` spans
3. Span attributes include: URL, status code, duration

### Test 3: User Interaction Tracing

1. Click any button (counter buttons, API call buttons)
2. Check Last9 for `click` spans
3. Span attributes include: element details, event type

### Test 4: Custom Span Tracing

1. Click **"External Users"** button (has custom span wrapper)
2. Check Last9 for `user.fetch_external_user_data` span
3. Span attributes include: custom business context

### Test 5: Counter Interactions

1. Click **"+ Increase"**, **"- Decrease"**, or **"Reset"** buttons
2. Check Last9 for `user.counter_interaction` spans
3. Span attributes include: action, previous value, new value

## 📁 Project Structure

```
angular/
├── src/
│   ├── app/
│   │   ├── app.ts                # Main component with UI interactions
│   │   ├── app.html              # Template with buttons/counters
│   │   ├── app.css               # Component styling
│   │   └── app.config.ts         # App configuration (HttpClient provider)
│   ├── telemetry.ts               # OpenTelemetry configuration
│   ├── main.ts                    # Bootstrap with telemetry init
│   ├── environment.ts             # Development config
│   ├── environment.prod.ts        # Production config
│   └── styles.css                 # Global styling
├── .env.example                   # Config template documentation
└── README.md                      # This file
```

## 🔍 Key Files Explained

### `src/telemetry.ts`

This is the core OpenTelemetry configuration file. It:
- Sets up the Web Tracer Provider
- Configures the OTLP exporter with Last9 endpoint
- Registers auto-instrumentations (fetch, document load, user interactions)
- Exports helper functions for custom spans

**Configuration is read from `window.__OTEL_CONFIG__`** which is set in `main.ts` from environment files.

### `src/main.ts`

The Angular app entry point that initializes telemetry:

```typescript
import { setupTelemetry } from './telemetry';
import { environment } from './environment';

// Configure OpenTelemetry from environment
(window as any).__OTEL_CONFIG__ = environment.otel;

// Initialize telemetry BEFORE Angular bootstraps
setupTelemetry();

// Bootstrap Angular application
bootstrapApplication(App, appConfig)
  .catch((err) => console.error(err));
```

**Important**: Telemetry must initialize BEFORE Angular bootstraps!

### `src/app/app.ts`

A demo Angular component showing:
- **Auto-instrumented interactions** - Counter buttons (automatically traced)
- **Custom spans** - External API calls with business context
- **Mixed approach** - Combining auto and custom instrumentation

### `src/environment.ts` and `src/environment.prod.ts`

Environment-specific configuration files:
- Development configuration with local settings
- Production configuration with production endpoints and tokens
- Angular automatically uses the correct file based on build configuration

## 🎓 Learning from This Example

### Automatic Instrumentation (Zero Code Changes)

The following are captured automatically:

```typescript
// ✅ Automatically traced - no code changes needed
<button (click)="handleCounterChange('increase', count + 1)">
  + Increase
</button>

// ✅ Automatically traced - no code changes needed
const response = await fetch('https://api.example.com/data');
```

### Custom Instrumentation (For Business Logic)

Add custom spans for business-critical operations:

```typescript
import { traceUserAction } from '../telemetry';

// ✅ Custom span with business context
await traceUserAction(
  'user.login',
  { 'user.email': email, 'auth.method': 'oauth' },
  async () => {
    // Your login logic here
  }
);
```

## 🔧 Configuration Options

### Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `otel.serviceName` | Yes | Service identifier in Last9 | `my-angular-app` |
| `otel.endpoint` | Yes | Last9 client monitoring endpoint<br/>Format: `<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces` | Use format with your actual values |
| `otel.apiToken` | Yes | Client token from [Ingestion Tokens](https://app.last9.io/control-plane/ingestion-tokens) | `your-client-token-here` |
| `otel.origin` | Yes | Allowed origin (must match token config) | `http://localhost:4200` |
| `otel.environment` | No | Environment identifier | `development`, `production` |

### Production Configuration

For production deployment, edit `src/environment.prod.ts`:

```typescript
export const environment = {
  production: true,
  otel: {
    serviceName: 'my-angular-app',
    endpoint: '<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces',
    apiToken: 'your-production-client-token',
    origin: 'https://yourdomain.com',
    environment: 'production'
  }
};
```

Build for production:
```bash
ng build --configuration production
```

**Important**:
- Create separate client tokens for dev and production with different origin restrictions!
- Get production token from [Ingestion Tokens](https://app.last9.io/control-plane/ingestion-tokens)
- See [RUM Getting Started Guide](https://last9.io/docs/rum-getting-started/) for detailed setup

## 🐛 Troubleshooting

### Issue: No telemetry in Last9

**Check browser console for errors:**

1. **Missing configuration error:**
   ```
   ❌ Missing required OpenTelemetry configuration
   ```
   **Solution**: Verify all required fields are set in `src/environment.ts`

2. **403 Forbidden error:**
   ```
   ❌ Failed to export spans: 403 Forbidden
   ```
   **Solution**:
   - Verify token is correct
   - Check token format includes "Bearer " prefix (automatically added)
   - Verify `otel.origin` matches token's allowed origins

3. **400 Bad Request error:**
   ```
   ❌ Failed to export spans: 400 Bad Request
   ```
   **Solution**:
   - Verify endpoint URL is correct
   - Check organization slug in endpoint URL

### Issue: Configuration not loading

**Angular requires rebuild after environment changes:**

```bash
# Stop the server (Ctrl+C)
ng serve
```

Environment files are compiled into the build, not read at runtime.

### Issue: CORS errors

**This shouldn't happen with Client Monitoring tokens**, but if you see CORS errors:

1. Verify you're using the Client Monitoring endpoint (contains `/client_monitoring/`)
2. Check token's allowed origins in Last9 dashboard
3. Ensure `otel.origin` matches your current origin exactly

### Issue: Too many spans / performance impact

**Adjust batch settings in `src/telemetry.ts`:**

```typescript
const spanProcessor = new BatchSpanProcessor(otlpExporter, {
  maxExportBatchSize: 512,      // Reduce to 256 or 128
  exportTimeoutMillis: 30000,   // Keep at 30s
  scheduledDelayMillis: 5000,   // Increase to 10000 for less frequent exports
});
```

### Issue: Sensitive data in spans

**Filter sensitive data in telemetry.ts:**

```typescript
new UserInteractionInstrumentation({
  enabled: true,
  eventNames: ['click', 'submit'],
  shouldPreventSpanCreation: (eventType, element) => {
    // Don't trace password inputs, sensitive forms, etc.
    if (element.type === 'password') return true;
    if (element.classList.contains('sensitive')) return true;
    return false;
  },
});
```

## 📚 Additional Resources

- **Last9 RUM Getting Started**: https://last9.io/docs/rum-getting-started/
- **Last9 Ingestion Tokens**: https://app.last9.io/control-plane/ingestion-tokens
- **OpenTelemetry Docs**: https://opentelemetry.io/docs/
- **Last9 Documentation**: https://docs.last9.io/
- **OpenTelemetry JavaScript**: https://github.com/open-telemetry/opentelemetry-js
- **Angular Documentation**: https://angular.dev/

## 🔒 Security Best Practices

### ✅ DO:
- Use Client Monitoring tokens for browser applications
- Set origin restrictions on all tokens
- Use separate tokens for dev/staging/production
- Rotate tokens periodically
- Filter sensitive data from spans

### ❌ DON'T:
- Use backend Authorization tokens in browsers
- Commit environment files with real tokens to version control
- Use production tokens in development
- Include passwords, API keys, or PII in span attributes
- Disable origin restrictions on tokens

## 💡 Next Steps

After running this demo:

1. **Integrate into your app** - Copy the telemetry setup to your own Angular application
2. **Customize telemetry.ts** - Add your own custom spans and attributes
3. **Explore Last9 dashboard** - Set up alerts, dashboards, and queries
4. **Add backend tracing** - Connect your Angular traces to backend services
5. **Deploy to production** - Use production tokens and proper configuration

## 📝 Available Scripts

```bash
# Start development server
npm start
# or
ng serve

# Build for production
npm run build
# or
ng build --configuration production

# Run tests
npm test
# or
ng test

# Run linter
npm run lint
# or
ng lint
```

## 🤝 Support

If you encounter issues:

1. Check the Troubleshooting section above
2. Review environment configuration in `src/environment.ts`
3. Check Last9 documentation at https://docs.last9.io/
4. Contact Last9 support for token/endpoint issues

## 📄 License

This example application is provided as-is for demonstration purposes.
