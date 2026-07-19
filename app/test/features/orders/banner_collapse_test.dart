import 'package:bakery_app/features/orders/widgets/urgency_banner.dart';
import 'package:bakery_app/features/orders/widgets/incomplete_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

extension on WidgetTester {
  Future<void> pumpBanner(Widget widget) {
    return pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: widget),
        ),
      ),
    );
  }
}

void main() {
  group('UrgencyBanner collapse/expand', () {
    testWidgets('expanded by default - shows full layout', (tester) async {
      await tester.pumpBanner(
        UrgencyBanner(
          criticalCount: 2,
          urgentCount: 1,
          onTap: () {},
        ),
      );

      expect(find.textContaining('Đơn hàng khẩn cấp'), findsOneWidget);
      expect(find.textContaining('2'), findsWidgets);
      expect(find.textContaining('1'), findsWidgets);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });

    testWidgets('collapses when chevron is tapped', (tester) async {
      await tester.pumpBanner(
        UrgencyBanner(
          criticalCount: 2,
          urgentCount: 1,
          onTap: () {},
        ),
      );

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsNothing);
    });

    testWidgets('re-expands when chevron is tapped again', (tester) async {
      await tester.pumpBanner(
        UrgencyBanner(
          criticalCount: 2,
          urgentCount: 1,
          onTap: () {},
        ),
      );

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });

    testWidgets('collapsed strip keeps count chips visible', (tester) async {
      await tester.pumpBanner(
        UrgencyBanner(
          criticalCount: 3,
          urgentCount: 2,
          onTap: () {},
        ),
      );

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();

      expect(find.textContaining('3'), findsOneWidget);
      expect(find.textContaining('2'), findsOneWidget);
    });

    testWidgets('collapsed strip navigates on body tap', (tester) async {
      var tapped = false;
      await tester.pumpBanner(
        UrgencyBanner(
          criticalCount: 1,
          urgentCount: 0,
          onTap: () => tapped = true,
        ),
      );

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();

      final inkWells = find.byType(InkWell);
      await tester.tapAt(
        tester.getRect(inkWells.last).center - const Offset(60, 0),
      );
      await tester.pumpAndSettle();

      expect(tapped, true);
    });
  });

  group('IncompleteBanner collapse/expand', () {
    testWidgets('expanded by default - shows full layout', (tester) async {
      await tester.pumpBanner(
        IncompleteBanner(
          count: 3,
          onTap: () {},
        ),
      );

      expect(find.textContaining('Đơn hàng thiếu thông tin'), findsOneWidget);
      expect(find.textContaining('3'), findsWidgets);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });

    testWidgets('collapses when chevron is tapped', (tester) async {
      await tester.pumpBanner(
        IncompleteBanner(
          count: 3,
          onTap: () {},
        ),
      );

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsNothing);
    });

    testWidgets('re-expands when chevron is tapped again', (tester) async {
      await tester.pumpBanner(
        IncompleteBanner(
          count: 3,
          onTap: () {},
        ),
      );

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });

    testWidgets('collapsed strip keeps count visible', (tester) async {
      await tester.pumpBanner(
        IncompleteBanner(
          count: 5,
          onTap: () {},
        ),
      );

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();

      expect(find.textContaining('5'), findsOneWidget);
    });

    testWidgets('collapsed strip navigates on body tap', (tester) async {
      var tapped = false;
      await tester.pumpBanner(
        IncompleteBanner(
          count: 1,
          onTap: () => tapped = true,
        ),
      );

      await tester.tap(find.byIcon(Icons.expand_less));
      await tester.pumpAndSettle();

      final inkWells = find.byType(InkWell);
      await tester.tapAt(
        tester.getRect(inkWells.last).center - const Offset(60, 0),
      );
      await tester.pumpAndSettle();

      expect(tapped, true);
    });
  });

  group('Independent collapse states', () {
    testWidgets('urgency and incomplete banners have independent state', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  UrgencyBanner(
                    criticalCount: 1, urgentCount: 0, onTap: () {},
                  ),
                  IncompleteBanner(count: 1, onTap: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.expand_less), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.expand_less).first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });
  });
}
