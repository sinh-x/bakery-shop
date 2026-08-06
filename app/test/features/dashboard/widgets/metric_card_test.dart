import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/dashboard/widgets/metric_card.dart';
import 'package:bakery_app/shared/labels/shared.dart';

void main() {
  testWidgets('renders label and value when value is provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MetricCard(
            icon: Icons.receipt_outlined,
            label: SharedLabels.dashboardMetricOrdersToday,
            value: '12',
          ),
        ),
      ),
    );
    expect(find.text(SharedLabels.dashboardMetricOrdersToday), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_outlined), findsOneWidget);
  });

  testWidgets('renders loading skeleton when value is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MetricCard(
            icon: Icons.receipt_outlined,
            label: SharedLabels.dashboardMetricOrdersToday,
            value: null,
          ),
        ),
      ),
    );
    expect(find.text(SharedLabels.dashboardMetricOrdersToday), findsOneWidget);
    // No value text rendered; the skeleton container is shown instead.
    expect(find.byType(Container), findsWidgets);
    expect(find.byIcon(Icons.receipt_outlined), findsOneWidget);
  });

  testWidgets('invokes onTap when tapped', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MetricCard(
            icon: Icons.receipt_outlined,
            label: SharedLabels.dashboardMetricOrdersToday,
            value: '12',
            onTap: () => tapped++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MetricCard));
    await tester.pump();
    expect(tapped, 1);
  });
}
