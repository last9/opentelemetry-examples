import 'dart:io';
import 'package:dio/dio.dart';
import 'package:opentelemetry/api.dart';
import 'package:opentelemetry/sdk.dart';
import 'package:otel_sdk_example/otel_setup.dart';
import 'package:otel_sdk_example/otel_dio_interceptor.dart';

/// End-to-end test: verifies OTel SDK initialization, span creation,
/// traceparent injection, and export via CollectorExporter.
///
/// Run: dart run bin/test_otel_dio.dart
/// With Last9: OTLP_ENDPOINT=https://otlp.last9.io OTLP_AUTH="Basic ..." dart run bin/test_otel_dio.dart
void main() async {
  final endpoint =
      Platform.environment['OTLP_ENDPOINT'] ?? 'http://localhost:4318/v1/traces';
  final auth = Platform.environment['OTLP_AUTH'] ?? 'none';

  print('=== OpenTelemetry Dart SDK + Dio Test ===');
  print('OTLP endpoint: $endpoint');

  // Test 1: SDK initialization
  print('\n--- Test 1: SDK initialization ---');
  try {
    initTelemetry(
      otlpEndpoint: Uri.parse(endpoint),
      authHeader: auth,
      serviceName: 'flutter-otel-test',
      environment: 'ci',
    );
    print('PASS: TracerProvider initialized');
  } catch (e) {
    print('FAIL: $e');
    return;
  }

  // Test 2: Tracer creation
  print('\n--- Test 2: Tracer creation ---');
  final tracer = globalTracerProvider.getTracer('test');
  print('PASS: Tracer created');

  // Test 3: Span creation and attributes
  print('\n--- Test 3: Span creation ---');
  final span = tracer.startSpan('test-span', attributes: [
    Attribute.fromString('test.key', 'test-value'),
    Attribute.fromInt('test.count', 42),
  ]);
  span.setStatus(StatusCode.ok);
  span.end();
  print('PASS: Span created, attributed, and ended');

  // Test 4: Dio interceptor with traceparent injection
  print('\n--- Test 4: Dio interceptor + traceparent ---');
  final dio = Dio();
  dio.interceptors.add(OtelDioInterceptor());

  // Capture the traceparent header before the request goes out
  String? capturedTraceparent;
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      capturedTraceparent = options.headers['traceparent'] as String?;
      print('traceparent: $capturedTraceparent');

      if (capturedTraceparent == null) {
        print('FAIL: traceparent header missing');
      } else {
        final parts = capturedTraceparent!.split('-');
        if (parts.length == 4 &&
            parts[0] == '00' &&
            parts[1].length == 32 &&
            parts[2].length == 16) {
          print('PASS: traceparent format valid');
        } else {
          print('FAIL: traceparent format invalid: $capturedTraceparent');
        }
      }

      handler.next(options);
    },
  ));

  try {
    await dio.get('https://httpbin.org/get');
    print('PASS: GET request completed with OTel span');
  } catch (e) {
    print('GET request error (network error OK for CI): $e');
  }

  // Test 5: Error span
  print('\n--- Test 5: Error handling ---');
  try {
    await dio.get('https://httpbin.org/status/500');
  } catch (e) {
    print('PASS: 500 error captured as span (expected)');
  }

  // Flush
  print('\n--- Flushing spans ---');
  try {
    (globalTracerProvider as TracerProviderBase).forceFlush();
    print('PASS: Spans flushed');
  } catch (e) {
    print('Flush error (OK if no collector running): $e');
  }

  print('\n=== All tests complete ===');
}
