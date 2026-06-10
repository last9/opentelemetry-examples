import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:last9_rum_flutter/last9_rum_flutter.dart';

import '../config.dart';
import '../event_log.dart';
import '../theme.dart';
import '../widgets.dart';

/// Profile tab — user identification, span attributes, custom events,
/// view/flush control, session info, SDK config, and the debug event log.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loggedIn = false;
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _loadSessionId();
  }

  Future<void> _loadSessionId() async {
    final String? id = await L9Rum.getSessionId();
    if (mounted) setState(() => _sessionId = id);
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: <Widget>[
          IconButton(
            onPressed: () => DebugLogSheet.show(context),
            icon: const Text('📋', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const FeatureBadge(features: <String>[
            'User Identification (identify / clearUser)',
            'Session Tracking (4h max / 30min inactivity)',
            'Head-based Sampling (sampleRate)',
            'Global Span Attributes',
            'Custom Events (addEvent)',
            'Resource Monitoring (CPU/memory)',
            'Flush Control',
          ]),
          _profileCard(),
          const Hint(
            'identify() sets user.id, user.name, user.email, user.full_name, '
            'user.roles as span attributes on all subsequent spans.',
          ),
          const SectionTitle('Global Span Attributes'),
          const Hint(
            'spanAttributes() adds key-value pairs to every span. Useful for '
            'A/B test variants, feature flags, etc.',
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: ActionButton(
                  emoji: '🏷️',
                  label: 'Set Attrs',
                  onTap: () async {
                    await L9Rum.spanAttributes(<String, dynamic>{
                      'app.experiment': 'checkout_v2',
                      'app.feature_flag': 'new_cart_enabled',
                      'app.build_type': 'debug',
                    });
                    addLog('spanAttributes: experiment=checkout_v2');
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ActionButton(
                  emoji: '🗑️',
                  label: 'Clear Attrs',
                  onTap: () async {
                    await L9Rum.spanAttributes(null);
                    addLog('spanAttributes: cleared');
                  },
                ),
              ),
            ],
          ),
          const SectionTitle('Custom Events'),
          const Hint('addEvent() creates a span event with custom attributes.'),
          Row(
            children: <Widget>[
              Expanded(
                child: ActionButton(
                  emoji: '👆',
                  label: 'Button Click',
                  onTap: () async {
                    await L9Rum.addEvent('button_click',
                        attributes: <String, dynamic>{
                          'button': 'purchase',
                          'screen': 'Profile',
                          'value': 99.99,
                        });
                    addLog('event: button_click (purchase)');
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ActionButton(
                  emoji: '⚡',
                  label: 'Feature Used',
                  onTap: () async {
                    await L9Rum.addEvent('feature_used',
                        attributes: <String, dynamic>{
                          'feature': 'dark_mode',
                          'enabled': true,
                          'platform': _platformName,
                        });
                    addLog('event: feature_used (dark_mode)');
                  },
                ),
              ),
            ],
          ),
          const SectionTitle('View & Export Control'),
          Row(
            children: <Widget>[
              Expanded(
                child: ActionButton(
                  emoji: '📱',
                  label: 'Set View Name',
                  onTap: () async {
                    await L9Rum.setViewName('CustomViewName');
                    addLog('setViewName: CustomViewName');
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ActionButton(
                  emoji: '📤',
                  label: 'Flush',
                  onTap: () async {
                    await L9Rum.flush();
                    addLog('flush() — exported pending spans');
                  },
                ),
              ),
            ],
          ),
          const SectionTitle('Session Info'),
          SessionCard(
            sessionId: _sessionId ?? 'loading…',
            hint: 'Sessions visible at: RUM → Sessions in the Last9 dashboard.\n'
                'Session timeout: 4h max / 30min inactivity.',
          ),
          const SizedBox(height: 12),
          const SectionTitle('Active SDK Config'),
          ConfigCard(rows: <List<String>>[
            <String>['serviceName', kServiceName],
            <String>['serviceVersion', kServiceVersion],
            <String>['appBuildId', kAppBuildId],
            <String>['environment', kDeploymentEnvironment],
            <String>['sampleRate', '$kSampleRate%'],
            <String>['networkInstrumentation', 'true'],
            <String>['propagationMode', 'preserve'],
            <String>['errorInstrumentation', 'true'],
            <String>['resourceMonitoring', 'true'],
            <String>['anrDetection', 'true'],
            <String>['baggage', 'true'],
            <String>['isolateTracePerRequest', 'false'],
          ]),
        ],
      ),
    );
  }

  Widget _profileCard() {
    return AppCard(
      radius: 16,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: <Widget>[
          CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.accent,
            child: Text(
              _loggedIn ? 'PW' : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _loggedIn ? 'Piyush Pawar' : 'Guest User',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            _loggedIn ? 'piyush@last9.io' : 'Not signed in',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          if (_loggedIn)
            OutlinedButton(
              onPressed: () async {
                await L9Rum.clearUser();
                if (!mounted) return;
                setState(() => _loggedIn = false);
                addLog('clearUser()');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: Color(0xFFDDDDDD)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              ),
              child: const Text('Sign Out',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            )
          else
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Sign In',
                onPressed: () async {
                  await L9Rum.identify(const L9UserInfo(
                    id: 'piyush-01',
                    name: 'Piyush',
                    email: 'piyush@last9.io',
                    fullName: 'Piyush Pawar',
                    roles: <String>['developer', 'admin'],
                  ));
                  if (!mounted) return;
                  setState(() => _loggedIn = true);
                  addLog('identify: Piyush Pawar (piyush-01)');
                },
              ),
            ),
        ],
      ),
    );
  }
}
