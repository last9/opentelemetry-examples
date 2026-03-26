import 'package:opentelemetry/api.dart';
import 'package:opentelemetry/sdk.dart';

/// Initialize OpenTelemetry with a CollectorExporter that sends spans
/// to Last9 via OTLP HTTP/protobuf.
///
/// Call this before runApp() in main.dart:
///   await initTelemetry();
void initTelemetry({
  required Uri otlpEndpoint,
  required String authHeader,
  String serviceName = 'flutter-app',
  String environment = 'production',
}) {
  final exporter = CollectorExporter(
    otlpEndpoint,
    headers: {'authorization': authHeader},
  );

  final provider = TracerProviderBase(
    processors: [BatchSpanProcessor(exporter)],
    resource: Resource([
      Attribute.fromString('service.name', serviceName),
      Attribute.fromString('deployment.environment', environment),
    ]),
  );

  registerGlobalTracerProvider(provider);
}
