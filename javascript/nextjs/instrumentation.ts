import { registerOTel } from "@vercel/otel";

export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    registerOTel();
  }
}

// import { NodeTracerProvider } from "@opentelemetry/sdk-trace-node";
// import { BatchSpanProcessor } from "@opentelemetry/sdk-trace-base";
// import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
// import { registerInstrumentations } from "@opentelemetry/instrumentation";
// import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";

// export async function register() {
//   if (process.env.NEXT_RUNTIME === "nodejs") {
//     const provider = new NodeTracerProvider();
//     const otlp = new OTLPTraceExporter();

//     provider.addSpanProcessor(new BatchSpanProcessor(otlp));
//     provider.register();

//     registerInstrumentations({
//       instrumentations: [
//         getNodeAutoInstrumentations({
//           "@opentelemetry/instrumentation-fs": {
//             enabled: false,
//           },
//         }),
//       ],
//     });
//   }
// }
