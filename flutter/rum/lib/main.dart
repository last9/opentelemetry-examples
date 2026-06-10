import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:last9_rum_flutter/last9_rum_flutter.dart';

import 'config.dart';
import 'event_log.dart';
import 'screens/errors_screen.dart';
import 'screens/home_screen.dart';
import 'screens/network_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/webview_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Mirror the reference app's rich init config.
  await L9Rum.initialize(L9RumConfig(
    baseUrl: kBaseUrl,
    clientToken: kClientToken,
    origin: kOrigin,
    serviceName: kServiceName,
    serviceVersion: kServiceVersion,
    appBuildId: kAppBuildId,
    deploymentEnvironment: kDeploymentEnvironment,
    sampleRate: kSampleRate,
    debugLogs: true,
    // Network & error auto-instrumentation.
    networkInstrumentation: true,
    errorInstrumentation: true,
    // Resource monitoring (CPU/memory).
    resourceMonitoringEnabled: true,
    resourceSamplingIntervalMs: 5000,
    // ANR detection (Android only).
    anrDetectionEnabled: true,
    anrThresholdMs: 5000,
    // Keep network spans on the view's trace so they surface in the
    // Sessions → APIs tab.
    isolateTracePerRequest: false,
    // Only suppress image/CDN resources; keep public API calls visible.
    ignorePatterns: L9NetworkIgnorePatterns(
      fullUrl: <L9UrlPattern>[
        L9UrlPattern.regex(
            RegExp(r'^https://images\.pexels\.com/photos/', caseSensitive: false)),
      ],
      pathname: <L9UrlPattern>[
        L9UrlPattern.regex(RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false)),
      ],
      hostname: <L9UrlPattern>[
        L9UrlPattern.regex(
            RegExp(r'(^|\.)loremflickr\.com$', caseSensitive: false)),
      ],
    ),
    // W3C Baggage propagation.
    baggage: const L9BaggageConfig(
      enabled: true,
      allowedKeys: <String>[
        'session.id',
        'user.id',
        'deployment.environment',
        'service.name',
      ],
    ),
    // Custom resource attributes.
    resourceAttributes: const <String, String>{
      'app.platform': 'flutter',
      'device.type': 'mobile',
    },
  ));

  addLog('L9Rum.initialize() complete');
  unawaited(L9Rum.getSessionId().then((String? id) {
    if (id != null && id.isNotEmpty) {
      addLog('sessionId: ${id.length > 12 ? id.substring(0, 12) : id}…');
    }
  }));

  // Forward Flutter framework errors to RUM.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    L9Rum.captureError(details.exception, stackTrace: details.stack);
  };

  // Forward errors that escape to the platform dispatcher.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    L9Rum.captureError(error, stackTrace: stack);
    return true;
  };

  // Forward async errors via a guarded zone.
  runZonedGuarded<void>(
    () => runApp(const MyApp()),
    (Object error, StackTrace stack) {
      L9Rum.captureError(error, stackTrace: stack);
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Last9 RUM Flutter Example',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Root observer: tracks the top-level shell route + logs route changes.
      // (Home owns its own nested Navigator + observer for Dashboard → Detail.)
      navigatorObservers: <NavigatorObserver>[
        L9NavigationObserver(),
        _LoggingNavigationObserver(),
      ],
      home: const RootShell(),
    );
  }
}

/// Logs route pushes/pops into the global event log (mirrors the reference's
/// `route → X` entries).
class _LoggingNavigationObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final String? name = route.settings.name;
    if (name != null && name.isNotEmpty) addLog('route → $name');
  }
}

/// The bottom-tab shell hosting the 5 tabs. Each tab is kept alive via an
/// [IndexedStack] so view/network state persists when switching tabs.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const List<Widget> _tabs = <Widget>[
    HomeScreen(),
    NetworkScreen(),
    WebViewScreen(),
    ErrorsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: _tabs),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
            (Set<WidgetState> states) => TextStyle(
              fontSize: 11,
              color: states.contains(WidgetState.selected)
                  ? AppColors.accent
                  : const Color(0xFF999999),
            ),
          ),
        ),
        child: NavigationBar(
          backgroundColor: Colors.white,
          indicatorColor: AppColors.featureBg,
          selectedIndex: _index,
          onDestinationSelected: (int i) => setState(() => _index = i),
          destinations: const <NavigationDestination>[
            NavigationDestination(
                icon: Text('🏠', style: TextStyle(fontSize: 20)), label: 'Home'),
            NavigationDestination(
                icon: Text('🌐', style: TextStyle(fontSize: 20)),
                label: 'Network'),
            NavigationDestination(
                icon: Text('🔗', style: TextStyle(fontSize: 20)),
                label: 'WebView'),
            NavigationDestination(
                icon: Text('⚠️', style: TextStyle(fontSize: 20)),
                label: 'Errors'),
            NavigationDestination(
                icon: Text('👤', style: TextStyle(fontSize: 20)),
                label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
