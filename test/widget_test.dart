// Smoke test for the TorqueDen app shell.
//
// We pump MainShell directly (wrapped in a MaterialApp) so the test doesn't
// need a live Supabase connection — it just verifies the UI shell renders and
// the 4-tab navigation is present.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:torqueden/main_shell.dart';

void main() {
  testWidgets('App shell shows Home and the 4-tab navigation', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainShell()));

    // Home tab content is visible on launch.
    expect(find.text('Your feed is quiet'), findsOneWidget);

    // All four navigation destinations are present.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Garage'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
