import 'package:bakery_app/features/orders/widgets/stage1_extras_states.dart';
import 'package:bakery_app/features/orders/widgets/stage1_responsive_content.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Stage1ResponsiveContent (DG-214 Phase 6, NFR-1)', () {
    testWidgets('fills width on phone (<600dp)', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stage1ResponsiveContent(
              child: SizedBox(key: key, width: double.infinity, height: 50),
            ),
          ),
        ),
      );

      final box = tester.getSize(find.byKey(key));
      expect(box.width, 360);
      expect(isTabletWidth(tester.element(find.byKey(key))), isFalse);
    });

    testWidgets('constrains width on tablet (>=600dp)', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stage1ResponsiveContent(
              child: SizedBox(key: key, width: double.infinity, height: 50),
            ),
          ),
        ),
      );

      final box = tester.getSize(find.byKey(key));
      expect(box.width, lessThan(1200));
      // Max content width constant is 720.
      expect(box.width, lessThanOrEqualTo(720));
      expect(isTabletWidth(tester.element(find.byKey(key))), isTrue);
    });
  });

  group('Stage1ExtrasLoading (DG-214 Phase 6, NFR-2)', () {
    testWidgets('shows loading label with progress indicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Stage1ExtrasLoading()),
        ),
      );

      expect(find.text(OrdersLabels.stage1ExtrasLoading), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Stage1ExtrasError (DG-214 Phase 6, NFR-1)', () {
    testWidgets('shows error label and retry button', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stage1ExtrasError(onRetry: () => retries++),
          ),
        ),
      );

      expect(find.text(OrdersLabels.stage1ExtrasLoadError), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text(VN.retry), findsOneWidget);

      await tester.tap(find.text(VN.retry));
      await tester.pump();
      expect(retries, 1);
    });
  });
}