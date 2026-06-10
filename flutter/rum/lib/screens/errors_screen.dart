import 'dart:async';

import 'package:flutter/material.dart';
import 'package:last9_rum_flutter/last9_rum_flutter.dart';

import '../event_log.dart';
import '../widgets.dart';

/// Errors tab — exercises every error path: manual captureError with context,
/// caught type/network errors, an unhandled async path, a deep stack, an ANR
/// simulation (busy-wait), an error burst, and an uncaught throw.
class ErrorsScreen extends StatelessWidget {
  const ErrorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Errors')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const FeatureBadge(features: <String>[
            'Manual Error Capture (captureError)',
            'Unhandled Dart Exception (errorInstrumentation)',
            'Async / Future Error Tracking',
            'ANR Detection (Android, 5s threshold)',
            'Stack Traces with Context',
          ]),
          const Hint(
            'errorInstrumentation: true auto-captures unhandled Dart errors. '
            'anrDetectionEnabled: true watches for main-thread blocks >5s '
            '(Android only).',
          ),
          ErrorButton(
            title: 'Capture Error (with context)',
            subtitle: 'captureError(err, context: { screen, severity, ... })',
            color: const Color(0xFFFF6B6B),
            onTap: () async {
              final Object err =
                  StateError('Checkout failed: payment gateway timeout');
              await L9Rum.captureError(err,
                  stackTrace: StackTrace.current,
                  context: <String, dynamic>{
                    'screen': 'Checkout',
                    'severity': 'high',
                    'user_action': 'submit_payment',
                    'cart_total': 149.99,
                  });
              addLog('captureError: payment gateway timeout');
            },
          ),
          ErrorButton(
            title: 'Capture TypeError',
            subtitle: 'Simulates accessing a member of null',
            color: const Color(0xFFFF9F43),
            onTap: () async {
              try {
                final List<int> empty = <int>[];
                empty.firstWhere((int e) => e > 0);
              } catch (e, st) {
                await L9Rum.captureError(e,
                    stackTrace: st,
                    context: <String, dynamic>{
                      'screen': 'ErrorsDemo',
                      'type': 'TypeError',
                    });
                addLog('captureError: TypeError');
              }
            },
          ),
          ErrorButton(
            title: 'Capture Network Error',
            subtitle: 'Simulates a failed API call error',
            color: const Color(0xFFEE5A24),
            onTap: () async {
              await L9Rum.captureError(
                Exception('NetworkError: Failed to fetch /todos'),
                stackTrace: StackTrace.current,
                context: <String, dynamic>{
                  'screen': 'Todos',
                  'endpoint': '/todos',
                  'http_method': 'GET',
                  'retry_count': 3,
                },
              );
              addLog('captureError: NetworkError');
            },
          ),
          ErrorButton(
            title: 'Unhandled Future Error',
            subtitle: 'Throws inside an async Future (auto-captured)',
            color: const Color(0xFF6C5CE7),
            onTap: () async {
              // Escapes to the guarded zone wired in main().
              unawaited(Future<void>.error(
                  Exception('Unhandled: session token expired')));
              // Also capture explicitly so it always shows up.
              await L9Rum.captureError(
                Exception('Unhandled: session token expired'),
                stackTrace: StackTrace.current,
                context: <String, dynamic>{'source': 'future_error'},
              );
              addLog('captureError: future error');
            },
          ),
          ErrorButton(
            title: 'Capture Error with Stack Trace',
            subtitle: 'Deep call stack to demonstrate trace capture',
            color: const Color(0xFFA29BFE),
            onTap: () async {
              void level3() => throw Exception(
                  'Deep stack: database connection pool exhausted');
              void level2() => level3();
              void level1() => level2();
              try {
                level1();
              } catch (e, st) {
                await L9Rum.captureError(e,
                    stackTrace: st,
                    context: <String, dynamic>{
                      'screen': 'ErrorsDemo',
                      'stack_depth': 3,
                    });
                addLog('captureError: deep stack trace');
              }
            },
          ),
          ErrorButton(
            title: 'ANR Simulation (Android only)',
            subtitle: 'Blocks the UI thread for ~3s — ANR watchdog may fire if >5s',
            color: const Color(0xFFFD79A8),
            onTap: () {
              addLog('starting ANR simulation (3s block)…');
              final DateTime end =
                  DateTime.now().add(const Duration(seconds: 3));
              while (DateTime.now().isBefore(end)) {
                // busy-wait to block the UI isolate
              }
              addLog('ANR simulation complete');
            },
          ),
          ErrorButton(
            title: 'Fire Multiple Errors (Burst)',
            subtitle: '5 rapid errors to test batching & export',
            color: const Color(0xFF00B894),
            onTap: () async {
              for (int i = 1; i <= 5; i++) {
                await L9Rum.captureError(
                  Exception('Burst error #$i'),
                  stackTrace: StackTrace.current,
                  context: <String, dynamic>{
                    'index': i,
                    'screen': 'ErrorsDemo',
                  },
                );
              }
              addLog('captureError: 5 burst errors');
            },
          ),
          ErrorButton(
            title: 'Throw Uncaught Error',
            subtitle: 'Escapes to the guarded zone / global handlers',
            color: const Color(0xFFD63031),
            onTap: () {
              addLog('throwing uncaught error');
              throw Exception('Demo UNCAUGHT error from Errors screen');
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
