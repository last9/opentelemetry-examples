# React + OpenTelemetry Example

1. Clone this project

```bash
npx degit last9/opentelemetry-examples/javascript/with-react with-react
```

2. Create `.env.local` file and add the following environment variables. You can
   obtain the values from the Last9 dashboard.

```env
VITE_OTLP_ENDPOINT=
VITE_OTLP_AUTH_HEADER=
```

3. To start the dev server run:

```
npm run dev
```

4. You can observe the frontend traces in the Last9 dashboard.
