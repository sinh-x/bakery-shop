import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:bakery_app/features/dashboard/management_dashboard_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const ManagementDashboardScreen(),
        ),
        GoRoute(
          path: '/accounting',
          builder: (_, _) => const SizedBox(child: Text('accounting-page')),
        ),
        GoRoute(
          path: '/stock',
          builder: (_, _) => const SizedBox(child: Text('stock-page')),
        ),
      ],
      initialLocation: '/dashboard',
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

void main() {
  testWidgets('renders app bar, section titles, and three metric cards',
      (tester) async {
    await _pump(tester);
    expect(find.text(VN.tabDashboard), findsOneWidget);
    expect(find.text('Chỉ số hôm nay'), findsOneWidget);
    expect(find.text('Truy cập nhanh'), findsOneWidget);
    // Three metric card labels (orders + revenue on screen, low-stock may
    // wrap offscreen — scroll back up to verify it after the alert check).
    expect(find.text('Đơn hàng hôm nay'), findsOneWidget);
    expect(find.text('Doanh thu hôm nay'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Tồn kho thấp'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    expect(find.text('Tồn kho thấp'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Cảnh báo'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    expect(find.text('Cảnh báo'), findsOneWidget);
  });

  testWidgets('renders five shortcut tiles', (tester) async {
    await _pump(tester);
    expect(find.text('Kho hàng'), findsOneWidget);
    expect(find.text('Quản lý danh mục'), findsOneWidget);
    expect(find.text('Quản lý khách hàng'), findsOneWidget);
    expect(find.text('Chi phí'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pump();
    expect(find.text('Quản lý phôi bánh'), findsOneWidget);
  });

  testWidgets('shortcut tap navigates via go router', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Kho hàng'), warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('stock-page'), findsOneWidget);
  });

  testWidgets('accounting menu navigates to accounting', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Kế toán'), findsWidgets);
    await tester.tap(find.text('Kế toán').last);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('accounting-page'), findsOneWidget);
  });

  testWidgets('refresh button is present', (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}