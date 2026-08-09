import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/dashboard/widgets/shortcut_grid.dart';
import 'package:bakery_app/shared/labels/shared.dart';

void main() {
  testWidgets('renders six shortcut tiles with expected labels',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShortcutGrid(onNavigate: (_) {}),
        ),
      ),
    );
    expect(find.text(SharedLabels.dashboardShortcutStock), findsOneWidget);
    expect(find.text(SharedLabels.dashboardShortcutCategories), findsOneWidget);
    expect(find.text(SharedLabels.dashboardShortcutCustomers), findsOneWidget);
    expect(find.text(SharedLabels.dashboardShortcutExpenses), findsOneWidget);
    expect(find.text(SharedLabels.dashboardShortcutBlanks), findsOneWidget);
    expect(find.text(SharedLabels.dashboardShortcutCashDrawer), findsOneWidget);
    expect(find.byType(ShortcutTile), findsNWidgets(6));
  });

  testWidgets('invokes onNavigate with the route when a tile is tapped',
      (tester) async {
    // Give the grid enough vertical space so all six tiles are hit-testable.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    String? tappedRoute;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShortcutGrid(onNavigate: (route) => tappedRoute = route),
        ),
      ),
    );
    await tester.tap(find.text(SharedLabels.dashboardShortcutStock));
    await tester.pump();
    expect(tappedRoute, '/stock');

    await tester.tap(find.text(SharedLabels.dashboardShortcutExpenses));
    await tester.pump();
    expect(tappedRoute, '/expenses');

    await tester.tap(find.text(SharedLabels.dashboardShortcutCashDrawer));
    await tester.pump();
    expect(tappedRoute, '/cash-drawer');
  });
}
