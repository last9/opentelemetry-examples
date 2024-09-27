const { NodeSDK } = require("@opentelemetry/sdk-node");
const {
  OTLPTraceExporter,
} = require("@opentelemetry/exporter-trace-otlp-http");
const { Resource } = require("@opentelemetry/resources");
const {
  SEMRESATTRS_SERVICE_NAME,
  SEMRESATTRS_DEPLOYMENT_ENVIRONMENT,
} = require("@opentelemetry/semantic-conventions");
const { BatchSpanProcessor } = require("@opentelemetry/sdk-trace-base");
const {
  getNodeAutoInstrumentations,
} = require("@opentelemetry/auto-instrumentations-node");

function setupOTel() {
  const exporter = new OTLPTraceExporter({
    url: "<last9_endpoint>/v1/traces",
    headers: {
      Authorization: "Bearer <last9_auth_header>",
    },
  });

  const sdk = new NodeSDK({
    resource: new Resource({
      [SEMRESATTRS_SERVICE_NAME]: "hono-app", // Replace with your service name
      [SEMRESATTRS_DEPLOYMENT_ENVIRONMENT]: process.env.NODE_ENVIRONMENT,
    }),
    traceExporter: exporter,
    instrumentations: [getNodeAutoInstrumentations()],
    spanProcessor: new BatchSpanProcessor(exporter),
  });

  sdk.start();

  process.on("SIGTERM", () => {
    sdk
      .shutdown()
      .then(() => console.log("SDK shut down successfully"))
      .catch((error) => console.log("Error shutting down SDK", error))
      .finally(() => process.exit(0));
  });

  return sdk;
}

module.exports = { setupOTel };
