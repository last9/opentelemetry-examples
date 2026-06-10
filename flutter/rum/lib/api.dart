import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'widgets.dart';

/// Tags attached to every demo request as query params + headers so the
/// requests are easy to filter in the Last9 dashboard.
class DemoRequestTags {
  const DemoRequestTags({required this.tab, required this.name});

  /// "home" or "network".
  final String tab;
  final String name;
}

/// A GET that also decodes JSON, returning both the parsed body and an
/// [ApiResult] suitable for the API-log cards.
class TimedJsonResult<T> {
  const TimedJsonResult({required this.data, required this.result});

  final T? data;
  final ApiResult result;
}

/// Adds the `l9_demo*` query params so requests are filterable in the
/// dashboard (mirrors the reference's `demoUrl`).
Uri demoUri(String url, DemoRequestTags tags) {
  final Uri base = Uri.parse(url);
  final Map<String, String> qp = Map<String, String>.from(
    base.queryParameters,
  )
    ..['l9_demo'] = 'true'
    ..['l9_demo_tab'] = tags.tab
    ..['l9_demo_request'] = tags.name;
  return base.replace(queryParameters: qp);
}

Map<String, String> demoHeaders(DemoRequestTags tags) => <String, String>{
      'Content-Type': 'application/json; charset=UTF-8',
      'X-L9-Demo': 'true',
      'X-L9-Demo-Tab': tags.tab,
      'X-L9-Demo-Request': tags.name,
    };

/// Generic request helper used by the Network tab's CRUD demos. Every call
/// goes through the `http` package (dart:io HttpClient), which the RUM SDK
/// auto-instruments when networkInstrumentation is enabled.
Future<ApiResult> api(
  String method,
  String path, {
  Object? body,
  DemoRequestTags? tags,
}) async {
  final DemoRequestTags t =
      tags ?? DemoRequestTags(tab: 'network', name: '$method $path');
  final Uri url = demoUri('$kApiBase$path', t);
  final Stopwatch sw = Stopwatch()..start();
  try {
    final http.Request req = http.Request(method, url)
      ..headers.addAll(demoHeaders(t));
    if (body != null) req.body = jsonEncode(body);
    final http.StreamedResponse streamed = await req.send();
    final http.Response res = await http.Response.fromStream(streamed);
    sw.stop();
    final String text = res.body;
    return ApiResult(
      label: '$method $path',
      method: method,
      path: path,
      status: res.statusCode,
      ok: res.statusCode >= 200 && res.statusCode < 300,
      durationMs: sw.elapsedMilliseconds,
      body: text.length > 500 ? text.substring(0, 500) : text,
    );
  } catch (e) {
    sw.stop();
    return ApiResult(
      label: '$method $path',
      method: method,
      path: path,
      status: 0,
      ok: false,
      durationMs: sw.elapsedMilliseconds,
      error: e.toString(),
    );
  }
}

/// A GET that decodes JSON and records timing — used by the Home dashboard's
/// parallel loads (posts/users/comments/httpbin delays).
Future<TimedJsonResult<T>> timedJson<T>(
  String label,
  String url,
  DemoRequestTags tags,
) async {
  final Uri requestUrl = demoUri(url, tags);
  final Stopwatch sw = Stopwatch()..start();
  try {
    final http.Response res =
        await http.get(requestUrl, headers: demoHeaders(tags));
    sw.stop();
    final String text = res.body;
    T? data;
    if (text.isNotEmpty) {
      data = jsonDecode(text) as T?;
    }
    return TimedJsonResult<T>(
      data: data,
      result: ApiResult(
        label: label,
        method: 'GET',
        path: requestUrl.toString(),
        status: res.statusCode,
        ok: res.statusCode >= 200 && res.statusCode < 300,
        durationMs: sw.elapsedMilliseconds,
        body: text.length > 500 ? text.substring(0, 500) : text,
      ),
    );
  } catch (e) {
    sw.stop();
    return TimedJsonResult<T>(
      data: null,
      result: ApiResult(
        label: label,
        method: 'GET',
        path: requestUrl.toString(),
        status: 0,
        ok: false,
        durationMs: sw.elapsedMilliseconds,
        error: e.toString(),
      ),
    );
  }
}

/// Public-API demo endpoints (Network tab "Run Public API Demo").
const List<({String label, String url})> kPublicApiDemos =
    <({String label, String url})>[
  (label: 'todos limit', url: '$kApiBase/todos?_limit=1'),
  (label: 'comments by post', url: '$kApiBase/comments?postId=1'),
  (label: 'user detail', url: '$kApiBase/users/1'),
  (label: 'album detail', url: '$kApiBase/albums/1'),
  (label: 'GitHub zen', url: 'https://api.github.com/zen'),
  (label: 'random dog image API', url: 'https://dog.ceo/api/breeds/image/random'),
];

/// Tracked-request demo endpoints (Network tab "Run Tracked Requests Demo").
const List<({String label, String url})> kTrackedNetworkDemos =
    <({String label, String url})>[
  (label: 'tracked posts list', url: '$kApiBase/posts?_limit=3'),
  (label: 'tracked todo detail', url: '$kApiBase/todos/2'),
  (label: 'tracked GitHub rate limit', url: 'https://api.github.com/rate_limit'),
];
