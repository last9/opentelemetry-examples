import 'dart:math';
import 'package:dio/dio.dart';

/// Injects a W3C traceparent header into every outbound HTTP request.
/// Downstream services (Lambda, .NET backends, on-prem APIs) will
/// continue the same trace automatically.
///
/// Usage:
///   final dio = Dio();
///   dio.interceptors.add(TraceparentInterceptor());
class TraceparentInterceptor extends Interceptor {
  final Random _rng = Random.secure();

  String _randomHex(int bytes) => List.generate(
        bytes,
        (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Format: 00-{16-byte trace-id}-{8-byte span-id}-01
    // 01 = sampled flag (tell downstream to record this trace)
    final traceId = _randomHex(16); // 32 hex chars
    final spanId = _randomHex(8); // 16 hex chars
    options.headers['traceparent'] = '00-$traceId-$spanId-01';
    handler.next(options);
  }
}
