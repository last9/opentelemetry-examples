import 'package:flutter/material.dart';
import 'package:last9_rum_flutter/last9_rum_flutter.dart';

import '../api.dart';
import '../config.dart';
import '../event_log.dart';
import '../theme.dart';
import '../widgets.dart';

/// Home tab — owns its own [Navigator] so view tracking fires on the
/// Dashboard → Detail push (the root [L9NavigationObserver] sees each route).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      observers: <NavigatorObserver>[L9NavigationObserver()],
      onGenerateRoute: (RouteSettings settings) {
        if (settings.name == DetailScreen.routeName) {
          final int postId = (settings.arguments as int?) ?? 1;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => DetailScreen(postId: postId),
          );
        }
        return MaterialPageRoute<void>(
          settings: const RouteSettings(name: DashboardScreen.routeName),
          builder: (_) => const DashboardScreen(),
        );
      },
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  static const String routeName = 'Home';

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<dynamic> _posts = <dynamic>[];
  List<dynamic> _users = <dynamic>[];
  List<dynamic> _comments = <dynamic>[];
  List<ApiResult> _homeRequests = <ApiResult>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    setState(() => _loading = true);
    await L9Rum.startView('Home');
    addLog('startView: Home');
    try {
      final List<TimedJsonResult<dynamic>> results =
          await Future.wait<TimedJsonResult<dynamic>>(<Future<TimedJsonResult<dynamic>>>[
        timedJson<List<dynamic>>('Home fast posts', '$kApiBase/posts?_limit=20',
            const DemoRequestTags(tab: 'home', name: 'posts-list')),
        timedJson<List<dynamic>>('Home fast users', '$kApiBase/users?_limit=5',
            const DemoRequestTags(tab: 'home', name: 'users-list')),
        timedJson<List<dynamic>>('Home fast comments',
            '$kApiBase/comments?postId=1',
            const DemoRequestTags(tab: 'home', name: 'comments-for-post')),
        timedJson<Map<String, dynamic>>('Home delayed 1s',
            'https://httpbin.org/delay/1',
            const DemoRequestTags(tab: 'home', name: 'delay-1s')),
        timedJson<Map<String, dynamic>>('Home delayed 3s',
            'https://httpbin.org/delay/3',
            const DemoRequestTags(tab: 'home', name: 'delay-3s')),
      ]);

      final List<ApiResult> requestResults =
          results.map((TimedJsonResult<dynamic> r) => r.result).toList();
      final ApiResult maxResult = requestResults.reduce(
        (ApiResult a, ApiResult b) => b.durationMs > a.durationMs ? b : a,
      );
      if (!mounted) return;
      setState(() {
        _posts = (results[0].data as List<dynamic>?) ?? <dynamic>[];
        _users = (results[1].data as List<dynamic>?) ?? <dynamic>[];
        _comments = (results[2].data as List<dynamic>?) ?? <dynamic>[];
        _homeRequests = requestResults;
      });
      addLog(
        'Home APIs complete; expected max view.ttfd source: '
        '${maxResult.label} (${maxResult.durationMs}ms)',
      );
    } catch (e) {
      addLog('Home APIs failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Posts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_loading)
            AppCard(
              child: Column(
                children: const <Widget>[
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                  Hint(
                    'Loading posts, users, and comments before the Home '
                    'screen is fully displayed.',
                  ),
                ],
              ),
            )
          else ...<Widget>[
            const FeatureBadge(features: <String>[
              'Home starts an active View before API requests',
              'Fast and delayed GET requests run before full content render',
              'SDK sets view.ttfd from the maximum request time on this view',
              'Home APIs include l9_demo_tab=home query tags',
            ]),
            SummaryCard(
              title: 'Home full display data',
              lines: <String>[
                '${_posts.length} posts',
                '${_users.length} users',
                '${_comments.length} comments for the featured post',
              ],
            ),
            const SectionTitle('TTFD Request Timings'),
            const Hint(
              'The delayed 3s request should usually be the max-duration '
              'source for view.ttfd. Filter dashboard URLs by '
              'l9_demo_tab=home or l9_demo_request=delay-3s.',
            ),
            for (final ApiResult r in _homeRequests) ApiResultCard(result: r),
            const SizedBox(height: 8),
            for (final dynamic post in _posts)
              _PostTile(
                post: post,
                onTap: () {
                  final int id = (post['id'] as num?)?.toInt() ?? 1;
                  L9Rum.addEvent('nav_tap',
                      attributes: <String, dynamic>{'destination': 'Post #$id'});
                  addLog('nav → Post #$id');
                  Navigator.of(context)
                      .pushNamed(DetailScreen.routeName, arguments: id);
                },
              ),
            const SectionTitle('Featured Users'),
            for (final dynamic user in _users)
              AppCard(
                radius: 8,
                leftBorderColor: AppColors.accent,
                leftBorderWidth: 3,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text((user['name'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    Text((user['email'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
            const SectionTitle('Featured Comments'),
            for (final dynamic c in _comments.take(3))
              AppCard(
                radius: 8,
                leftBorderColor: AppColors.ok,
                leftBorderWidth: 3,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text((c['name'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    Text((c['body'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            fontFamily: 'monospace')),
                  ],
                ),
              ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post, required this.onTap});

  final dynamic post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 10,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  (post['title'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  (post['body'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const Text('›',
              style: TextStyle(fontSize: 20, color: Color(0xFFCCCCCC))),
        ],
      ),
    );
  }
}

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.postId});

  static const String routeName = 'Detail';

  final int postId;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Map<String, dynamic>? _post;
  List<dynamic> _comments = <dynamic>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final int id = widget.postId;
    const DemoRequestTags postTags =
        DemoRequestTags(tab: 'home', name: 'detail-post');
    const DemoRequestTags commentsTags =
        DemoRequestTags(tab: 'home', name: 'detail-comments');
    final List<TimedJsonResult<dynamic>> results =
        await Future.wait<TimedJsonResult<dynamic>>(<Future<TimedJsonResult<dynamic>>>[
      timedJson<Map<String, dynamic>>(
          'Detail post', '$kApiBase/posts/$id', postTags),
      timedJson<List<dynamic>>(
          'Detail comments', '$kApiBase/posts/$id/comments', commentsTags),
    ]);
    if (!mounted) return;
    setState(() {
      _post = results[0].data as Map<String, dynamic>?;
      _comments = (results[1].data as List<dynamic>?) ?? <dynamic>[];
      _loading = false;
    });
    addLog('GET /posts/$id → ${results[0].result.status}');
    addLog(
        'GET /posts/$id/comments → ${results[1].result.status} (${_comments.length})');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('← Back',
              style: TextStyle(
                  fontSize: 14,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600)),
        ),
        leadingWidth: 80,
        title: Text('Post #${widget.postId}'),
      ),
      body: _loading
          ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator()))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                SectionTitle((_post?['title'] ?? '').toString()),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text((_post?['body'] ?? '').toString(),
                      style: AppText.hint),
                ),
                SectionTitle('Comments (${_comments.length})'),
                for (final dynamic c in _comments)
                  AppCard(
                    radius: 8,
                    leftBorderColor: AppColors.accent,
                    leftBorderWidth: 3,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text((c['name'] ?? '').toString(),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        Text((c['email'] ?? '').toString(),
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textMuted)),
                        const SizedBox(height: 4),
                        Text((c['body'] ?? '').toString(),
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                                fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}
