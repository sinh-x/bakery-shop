import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/dashboard/widgets/alert_section.dart';
import 'package:bakery_app/shared/labels/shared.dart';

void _noop() {}

void main() {
  testWidgets('renders nothing when count is 0', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlertSection(count: 0, onTap: () {}),
        ),
      ),
    );
    expect(find.byType(AlertSection), findsWidgets);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('renders banner when count > 0', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AlertSection(count: 3, onTap: _noop),
        ),
      ),
    );
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text(SharedLabels.dashboardCriticalOrdersAlert(3)), findsOneWidget);
  });

  testWidgets('invokes onTap when banner is tapped', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlertSection(count: 2, onTap: () => tapped++),
        ),
      ),
    );
    await tester.tap(find.byType(AlertSection));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('shows dismiss button when onDismiss is provided', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlertSection(
            count: 1,
            onTap: () {},
            onDismiss: () => dismissed++,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(dismissed, 1);
  });
}
