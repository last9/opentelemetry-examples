// Smoke test for the Last9 RUM Flutter example.
//
// The full app initializes L9Rum (a platform-channel plugin) and the Home
// dashboard performs network calls on load, neither of which runs under
// flutter_test without a native binding / live network. So this test renders a
// pure design-system widget (FeatureBadge) to verify the UI layer builds.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rum_flutter_example/widgets.dart';

void main() {
  testWidgets('FeatureBadge renders its feature list', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FeatureBadge(features: <String>['Network instrumentation', 'Error capture']),
        ),
      ),
    );

    expect(find.text('RUM FEATURES ON THIS SCREEN'), findsOneWidget);
    expect(find.textContaining('Network instrumentation'), findsOneWidget);
    expect(find.textContaining('Error capture'), findsOneWidget);
  });
}
