# Express OpenTelemetry Auto Instrumentation Example

1. To clone this example run the following command:

```bash
npx degit last9/opentelemetry-examples/javascript/with-express-ts with-express-ts
```

2. In `/env` folder create `.env` file and add the contents of `.env.example`
   file

3. Obtain the OTLP endpoint and the Auth Header from the Last9 dashboard and
   modify the values of the `OTLP_ENDPOINT` and `OTLP_AUTH_HEADER` variables
   accordingly.

4. To build the project, execute the following command:

```bash
npm run build
```

5. Start the server and observe the traces in the Last9 dashboard.

```bash
npm run start
```
