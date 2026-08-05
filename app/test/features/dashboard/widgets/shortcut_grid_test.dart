import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/dashboard/widgets/shortcut_grid.dart';

void main() {
  testWidgets('renders five shortcut tiles with expected labels',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShortcutGrid(onNavigate: (_) {}),
        ),
      ),
    );
    expect(find.text('Kho hàng'), findsOneWidget);
    expect(find.text('Quản lý danh mục'), findsOneWidget);
    expect(find.text('Quản lý khách hàng'), findsOneWidget);
    expect(find.text('Chi phí'), findsOneWidget);
    expect(find.text('Quản lý phôi bánh'), findsOneWidget);
    expect(find.byType(ShortcutTile), findsNWidgets(5));
  });

  testWidgets('invokes onNavigate with the route when a tile is tapped',
      (tester) async {
    String? tappedRoute;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShortcutGrid(onNavigate: (route) => tappedRoute = route),
        ),
      ),
    );
    await tester.tap(find.text('Kho hàng'));
    await tester.pump();
    expect(tappedRoute, '/stock');

    await tester.tap(find.text('Chi phí'));
    await tester.pump();
    expect(tappedRoute, '/expenses');
  });
}