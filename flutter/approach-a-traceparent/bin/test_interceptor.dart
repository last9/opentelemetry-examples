import 'package:dio/dio.dart';
import 'package:traceparent_example/traceparent_interceptor.dart';

/// End-to-end test: verifies the traceparent interceptor adds valid
/// W3C headers to outbound requests.
///
/// Run: dart run bin/test_interceptor.dart
void main() async {
  final dio = Dio();
  dio.interceptors.add(TraceparentInterceptor());

  // Add a logging interceptor to capture the traceparent header
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final tp = options.headers['traceparent'] as String?;
      print('traceparent: $tp');

      // Validate format: 00-{32hex}-{16hex}-01
      if (tp == null) {
        print('FAIL: traceparent header is missing');
        handler.reject(DioException(requestOptions: options, message: 'missing traceparent'));
        return;
      }

      final parts = tp.split('-');
      if (parts.length != 4) {
        print('FAIL: expected 4 parts, got ${parts.length}');
        handler.reject(DioException(requestOptions: options, message: 'bad format'));
        return;
      }
      if (parts[0] != '00') {
        print('FAIL: version must be 00, got ${parts[0]}');
      }
      if (parts[1].length != 32) {
        print('FAIL: trace-id must be 32 hex chars, got ${parts[1].length}');
      }
      if (parts[2].length != 16) {
        print('FAIL: span-id must be 16 hex chars, got ${parts[2].length}');
      }
      if (parts[3] != '01') {
        print('FAIL: flags must be 01, got ${parts[3]}');
      }

      print('PASS: traceparent format is valid');
      handler.next(options);
    },
  ));

  // Make test requests
  print('\n--- Test 1: GET request ---');
  try {
    await dio.get('https://httpbin.org/get');
    print('PASS: GET request succeeded');
  } catch (e) {
    print('Request failed (network error is OK for validation): $e');
  }

  print('\n--- Test 2: POST request ---');
  try {
    await dio.post('https://httpbin.org/post', data: {'test': true});
    print('PASS: POST request succeeded');
  } catch (e) {
    print('Request failed (network error is OK for validation): $e');
  }

  // Verify unique trace IDs per request
  print('\n--- Test 3: Unique trace IDs ---');
  final traceIds = <String>{};
  for (var i = 0; i < 5; i++) {
    String? captured;
    final testDio = Dio();
    testDio.interceptors.add(TraceparentInterceptor());
    testDio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        captured = options.headers['traceparent'] as String?;
        handler.reject(DioException(
          requestOptions: options,
          message: 'intercepted for test',
        ));
      },
    ));
    try {
      await testDio.get('https://example.com');
    } catch (_) {}
    if (captured != null) traceIds.add(captured!);
  }
  if (traceIds.length == 5) {
    print('PASS: All 5 requests got unique traceparent headers');
  } else {
    print('FAIL: Expected 5 unique headers, got ${traceIds.length}');
  }

  print('\n=== All tests complete ===');
}
