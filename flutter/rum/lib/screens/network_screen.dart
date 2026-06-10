import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../event_log.dart';
import '../theme.dart';
import '../widgets.dart';

/// Network tab — todos CRUD over the `http` package (auto-instrumented),
/// plus public-API and tracked-request demo runners and an API log.
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  final TextEditingController _titleController = TextEditingController();
  final List<ApiResult> _results = <ApiResult>[];
  List<Map<String, dynamic>> _todos = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _publicApiLoading = false;
  bool _trackedLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTodos();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadTodos() async {
    setState(() => _loading = true);
    final ApiResult r = await api('GET', '/todos?_limit=10',
        tags: const DemoRequestTags(tab: 'network', name: 'todos-list'));
    List<Map<String, dynamic>> parsed = <Map<String, dynamic>>[];
    try {
      parsed = (jsonDecode(r.body ?? '[]') as List<dynamic>)
          .cast<Map<String, dynamic>>();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _todos = parsed;
      _results.insert(0, r);
      _loading = false;
    });
    addLog('GET /todos → ${r.status} (${r.durationMs}ms)');
  }

  Future<void> _createTodo() async {
    final String title = _titleController.text.trim();
    if (title.isEmpty) return;
    final ApiResult r = await api('POST', '/todos',
        body: <String, dynamic>{
          'title': title,
          'completed': false,
          'userId': 1,
        },
        tags: const DemoRequestTags(tab: 'network', name: 'todo-create'));
    if (!mounted) return;
    setState(() {
      _results.insert(0, r);
      try {
        final Map<String, dynamic> created =
            jsonDecode(r.body ?? '{}') as Map<String, dynamic>;
        _todos.insert(0, created);
      } catch (_) {}
    });
    addLog('POST /todos → ${r.status} (${r.durationMs}ms)');
    _titleController.clear();
  }

  Future<void> _toggleTodo(Map<String, dynamic> todo) async {
    final int id = (todo['id'] as num?)?.toInt() ?? 0;
    final ApiResult r = await api('PATCH', '/todos/$id',
        body: <String, dynamic>{'completed': !(todo['completed'] == true)},
        tags: const DemoRequestTags(tab: 'network', name: 'todo-toggle'));
    if (!mounted) return;
    setState(() {
      _results.insert(0, r);
      for (final Map<String, dynamic> t in _todos) {
        if (t['id'] == todo['id']) t['completed'] = !(t['completed'] == true);
      }
    });
    addLog('PATCH /todos/$id → ${r.status} (${r.durationMs}ms)');
  }

  Future<void> _deleteTodo(int id) async {
    final ApiResult r = await api('DELETE', '/todos/$id',
        tags: const DemoRequestTags(tab: 'network', name: 'todo-delete'));
    if (!mounted) return;
    setState(() {
      _results.insert(0, r);
      _todos.removeWhere((Map<String, dynamic> t) => t['id'] == id);
    });
    addLog('DELETE /todos/$id → ${r.status} (${r.durationMs}ms)');
  }

  Future<void> _runDemos(
    List<({String label, String url})> demos, {
    required String labelPrefix,
    required String logName,
    required void Function(bool) setLoading,
  }) async {
    setState(() => setLoading(true));
    final List<ApiResult> out =
        await Future.wait<ApiResult>(demos.map((({String label, String url}) d) async {
      final DemoRequestTags tags = DemoRequestTags(
        tab: 'network',
        name: '${labelPrefix == 'PUBLIC API' ? 'public-' : ''}'
            '${d.label.replaceAll(RegExp(r'\s+'), '-').toLowerCase()}',
      );
      final Uri url = demoUri(d.url, tags);
      final Stopwatch sw = Stopwatch()..start();
      try {
        final http.Response res =
            await http.get(url, headers: demoHeaders(tags));
        sw.stop();
        return ApiResult(
          label: '$labelPrefix ${d.label}',
          method: 'GET',
          path: url.toString(),
          status: res.statusCode,
          ok: res.statusCode >= 200 && res.statusCode < 300,
          durationMs: sw.elapsedMilliseconds,
          body: labelPrefix == 'PUBLIC API'
              ? 'Tracked by RUM network instrumentation and should appear in '
                  'the Last9 dashboard.'
              : (res.body.length > 500
                  ? res.body.substring(0, 500)
                  : res.body),
        );
      } catch (e) {
        sw.stop();
        return ApiResult(
          label: '$labelPrefix ${d.label}',
          method: 'GET',
          path: url.toString(),
          status: 0,
          ok: false,
          durationMs: sw.elapsedMilliseconds,
          error: e.toString(),
        );
      }
    }));
    if (!mounted) return;
    setState(() {
      _results.insertAll(0, out);
      setLoading(false);
    });
    addLog('$logName → ${out.length} captured requests');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Todos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const FeatureBadge(features: <String>[
            'GET /todos (list)',
            'POST /todos (create)',
            'PATCH /todos/:id (toggle)',
            'DELETE /todos/:id (remove)',
            'public API demos visible in the dashboard',
            'ignorePatterns only suppress image/CDN resources',
            'Network APIs include l9_demo_tab=network query tags',
          ]),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _titleController,
                  onSubmitted: (_) => _createTodo(),
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'New todo...',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    filled: true,
                    fillColor: Colors.white,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: PrimaryButton(label: 'Add', onPressed: _createTodo),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator()),
            )
          else
            for (final Map<String, dynamic> todo in _todos)
              _TodoTile(
                todo: todo,
                onToggle: () => _toggleTodo(todo),
                onDelete: () =>
                    _deleteTodo((todo['id'] as num?)?.toInt() ?? 0),
              ),
          const SectionTitle('Public API Requests'),
          const Hint(
            'Sends public API requests across JSONPlaceholder, GitHub, and '
            'dog.ceo. These no longer match ignorePatterns, so they should '
            'create network spans and appear in the Last9 dashboard. '
            'Image/CDN patterns are still ignored. Filter by l9_demo_tab=network.',
          ),
          PrimaryButton(
            label: _publicApiLoading
                ? 'Sending public API requests...'
                : 'Run Public API Demo',
            onPressed: _publicApiLoading
                ? null
                : () => _runDemos(
                      kPublicApiDemos,
                      labelPrefix: 'PUBLIC API',
                      logName: 'public API demo',
                      setLoading: (bool v) => _publicApiLoading = v,
                    ),
          ),
          const SectionTitle('Tracked Network Requests'),
          const Hint(
            'Sends requests that do not match ignorePatterns, so these should '
            'create network spans and appear in the Last9 dashboard. Filter by '
            'l9_demo_tab=network or l9_demo_request.',
          ),
          PrimaryButton(
            label: _trackedLoading
                ? 'Sending tracked requests...'
                : 'Run Tracked Requests Demo',
            onPressed: _trackedLoading
                ? null
                : () => _runDemos(
                      kTrackedNetworkDemos,
                      labelPrefix: 'TRACKED',
                      logName: 'tracked demo',
                      setLoading: (bool v) => _trackedLoading = v,
                    ),
          ),
          if (_results.isNotEmpty) ...<Widget>[
            const SectionTitle('API Log'),
            for (final ApiResult r in _results.take(10))
              ApiResultCard(result: r),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.todo,
    required this.onToggle,
    required this.onDelete,
  });

  final Map<String, dynamic> todo;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final bool completed = todo['completed'] == true;
    return AppCard(
      radius: 10,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(completed ? '✅' : '⬜',
                  style: const TextStyle(fontSize: 18)),
            ),
          ),
          Expanded(
            child: Text(
              (todo['title'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: completed ? const Color(0xFF999999) : AppColors.textPrimary,
                decoration:
                    completed ? TextDecoration.lineThrough : TextDecoration.none,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: const Text('✕',
                style: TextStyle(fontSize: 16, color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
