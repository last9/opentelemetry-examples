import 'package:dio/dio.dart';
import 'package:opentelemetry/api.dart';

/// TextMapSetter implementation for dio headers.
class _DioHeaderSetter implements TextMapSetter<Map<String, dynamic>> {
  @override
  void set(Map<String, dynamic> carrier, String key, String value) {
    carrier[key] = value;
  }
}

/// Dio interceptor that creates OpenTelemetry spans for every HTTP call
/// and injects W3C traceparent headers for downstream propagation.
///
/// Usage:
///   dio.interceptors.add(OtelDioInterceptor());
class OtelDioInterceptor extends Interceptor {
  final Tracer _tracer = globalTracerProvider.getTracer('flutter-http');
  final Map<RequestOptions, Span> _spans = {};
  final _setter = _DioHeaderSetter();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final span = _tracer.startSpan(
      '${options.method} ${options.path}',
      kind: SpanKind.client,
      attributes: [
        Attribute.fromString('http.method', options.method),
        Attribute.fromString('http.url', options.uri.toString()),
        Attribute.fromString('http.host', options.uri.host),
      ],
    );

    // Inject W3C traceparent header for downstream propagation
    final ctx = contextWithSpan(Context.current, span);
    W3CTraceContextPropagator().inject(ctx, options.headers, _setter);

    _spans[options] = span;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final span = _spans.remove(response.requestOptions);
    if (span != null) {
      span.setAttribute(
          Attribute.fromInt('http.status_code', response.statusCode ?? 0));
      span.end();
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final span = _spans.remove(err.requestOptions);
    if (span != null) {
      span.setAttribute(
          Attribute.fromString('error.message', err.message ?? 'unknown'));
      if (err.response?.statusCode != null) {
        span.setAttribute(
            Attribute.fromInt('http.status_code', err.response!.statusCode!));
      }
      span.setStatus(StatusCode.error, err.message ?? '');
      span.end();
    }
    handler.next(err);
  }
}
