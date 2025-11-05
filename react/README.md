# React OpenTelemetry Demo App - Last9 Integration

A complete reference example showing how to instrument a React application with OpenTelemetry and send telemetry data to Last9. This demo includes automatic instrumentation for page loads, HTTP requests, and user interactions.

## 🎯 What This Demo Includes

- ✅ **Auto-instrumented page loads** - Capture page performance metrics
- ✅ **Auto-instrumented HTTP requests** - Track all fetch/XHR calls
- ✅ **Auto-instrumented user interactions** - Monitor button clicks and form submissions
- ✅ **Custom span examples** - Track specific business operations
- ✅ **Distributed tracing ready** - Propagate trace context to backends
- ✅ **Production-ready configuration** - Secure token handling and environment separation

## 📋 Prerequisites

- Node.js 14+ and npm
- A Last9 account with access to Client Monitoring tokens
- Basic knowledge of React and OpenTelemetry concepts

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
3. Set the allowed origin to `http://localhost:3000` (for local development)
4. Copy the generated token

**Important**: Use Client Tokens for browser apps, NOT backend authorization tokens!

**Additional Resources:**
- [Getting Started with RUM](https://last9.io/docs/rum-getting-started/)

### Step 3: Configure Environment Variables

Create a `.env` file in the project root:

```bash
# Copy the example file
cp .env.example .env
```

Edit `.env` and add your configuration:

```bash
# Service name (appears in Last9 dashboard)
REACT_APP_OTEL_SERVICE_NAME=react-demo-app

# Last9 OTLP endpoint for your organization
# Format: <your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces
REACT_APP_OTEL_ENDPOINT=<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces

# Your Client Token (from Step 2)
REACT_APP_OTEL_API_TOKEN=your-client-token-here

# Allowed origin (must match token configuration)
REACT_APP_OTEL_ORIGIN=http://localhost:3000

# Environment identifier
REACT_APP_OTEL_ENVIRONMENT=development
```

**Replace**:
- In `REACT_APP_OTEL_ENDPOINT`: Replace `<your-base-url>` and `<your-org-slug>` with your actual values
- In `REACT_APP_OTEL_API_TOKEN`: Your client token from Ingestion Tokens page

### Step 4: Start the Application

```bash
npm start
```

The app will open at `http://localhost:3000` and automatically start sending telemetry to Last9.

### Step 5: Verify Telemetry

**In Browser Console:**

You should see initialization messages:
```
🚀 Initializing OpenTelemetry for React App...
✅ OpenTelemetry initialized successfully!
📊 Service: react-demo-app
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
- Traces from service: `react-demo-app`
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
react_app/
├── src/
│   ├── telemetry.ts          # OpenTelemetry configuration
│   ├── index.tsx              # App entry point (initializes telemetry)
│   ├── App.tsx                # Demo app with instrumented interactions
│   └── index.css              # Styling
├── .env                       # Your configuration (create this)
├── .env.example               # Configuration template
├── react-integration.md       # Complete integration guide
└── README.md                  # This file
```

## 🔍 Key Files Explained

### `src/telemetry.ts`

This is the core OpenTelemetry configuration file. It:
- Sets up the Web Tracer Provider
- Configures the OTLP exporter with Last9 endpoint
- Registers auto-instrumentations (fetch, document load, user interactions)
- Exports helper functions for custom spans

**No modifications needed** - it reads configuration from environment variables.

### `src/index.tsx`

The React app entry point that initializes telemetry:

```typescript
import setupTelemetry from './telemetry';

// Initialize telemetry BEFORE rendering the app
setupTelemetry();

// ... rest of React app initialization
```

### `src/App.tsx`

A demo React component showing:
- **Auto-instrumented interactions** - Counter buttons (automatically traced)
- **Custom spans** - External API calls with business context
- **Mixed approach** - Combining auto and custom instrumentation

## 🎓 Learning from This Example

### Automatic Instrumentation (Zero Code Changes)

The following are captured automatically:

```typescript
// ✅ Automatically traced - no code changes needed
<button onClick={() => setCount(count + 1)}>
  Increase
</button>

// ✅ Automatically traced - no code changes needed
const response = await fetch('https://api.example.com/data');
```

### Custom Instrumentation (For Business Logic)

Add custom spans for business-critical operations:

```typescript
import { traceUserAction } from './telemetry';

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
| `REACT_APP_OTEL_SERVICE_NAME` | Yes | Service identifier in Last9 | `my-react-app` |
| `REACT_APP_OTEL_ENDPOINT` | Yes | Last9 client monitoring endpoint<br/>Format: `<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces` | Use format with your actual values |
| `REACT_APP_OTEL_API_TOKEN` | Yes | Client token from [Ingestion Tokens](https://app.last9.io/control-plane/ingestion-tokens) | `your-client-token-here` |
| `REACT_APP_OTEL_ORIGIN` | Yes | Allowed origin (must match token config) | `http://localhost:3000` |
| `REACT_APP_OTEL_ENVIRONMENT` | No | Environment identifier | `development`, `production` |

### Production Configuration

For production deployment, create `.env.production`:

```bash
REACT_APP_OTEL_SERVICE_NAME=my-react-app
# Use your actual base URL and organization slug
REACT_APP_OTEL_ENDPOINT=<your-base-url>/v1/otlp/organizations/<your-org-slug>/telemetry/client_monitoring/v1/traces
REACT_APP_OTEL_API_TOKEN=your-production-client-token
REACT_APP_OTEL_ORIGIN=https://yourdomain.com
REACT_APP_OTEL_ENVIRONMENT=production
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
   **Solution**: Verify all required environment variables are set in `.env`

2. **403 Forbidden error:**
   ```
   ❌ Failed to export spans: 403 Forbidden
   ```
   **Solution**:
   - Verify token is correct
   - Check token format includes "Bearer " prefix (automatically added)
   - Verify `REACT_APP_OTEL_ORIGIN` matches token's allowed origins

3. **400 Bad Request error:**
   ```
   ❌ Failed to export spans: 400 Bad Request
   ```
   **Solution**:
   - Verify endpoint URL is correct
   - Check organization slug in endpoint URL

### Issue: Environment variables not loading

**Create React App requires restart after .env changes:**

```bash
# Stop the server (Ctrl+C)
npm start
```

Environment variables are baked into the build at compile time, not runtime.

### Issue: CORS errors

**This shouldn't happen with Client Monitoring tokens**, but if you see CORS errors:

1. Verify you're using the Client Monitoring endpoint (contains `/client_monitoring/`)
2. Check token's allowed origins in Last9 dashboard
3. Ensure `REACT_APP_OTEL_ORIGIN` matches your current origin exactly

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

- **Complete Integration Guide**: See `react-integration.md` for step-by-step integration instructions
- **Last9 RUM Getting Started**: https://last9.io/docs/rum-getting-started/
- **Last9 Ingestion Tokens**: https://app.last9.io/control-plane/ingestion-tokens
- **OpenTelemetry Docs**: https://opentelemetry.io/docs/
- **Last9 Documentation**: https://docs.last9.io/
- **OpenTelemetry JavaScript**: https://github.com/open-telemetry/opentelemetry-js

## 🔒 Security Best Practices

### ✅ DO:
- Use Client Monitoring tokens for browser applications
- Set origin restrictions on all tokens
- Use separate tokens for dev/staging/production
- Rotate tokens periodically
- Filter sensitive data from spans

### ❌ DON'T:
- Use backend Authorization tokens in browsers
- Commit `.env` files to version control (add to `.gitignore`)
- Use production tokens in development
- Include passwords, API keys, or PII in span attributes
- Disable origin restrictions on tokens

## 💡 Next Steps

After running this demo:

1. **Review `react-integration.md`** - Complete guide for integrating into your own app
2. **Customize telemetry.ts** - Add your own custom spans and attributes
3. **Explore Last9 dashboard** - Set up alerts, dashboards, and queries
4. **Add backend tracing** - Connect your React traces to backend services
5. **Deploy to production** - Use production tokens and proper configuration

## 📝 Available Scripts

```bash
# Start development server
npm start

# Build for production
npm run build

# Run tests
npm test

# Eject from Create React App (irreversible)
npm run eject
```

## 🤝 Support

If you encounter issues:

1. Check the Troubleshooting section above
2. Review `react-integration.md` for detailed documentation
3. Check Last9 documentation at https://docs.last9.io/
4. Contact Last9 support for token/endpoint issues

## 📄 License

This example application is provided as-is for demonstration purposes.
