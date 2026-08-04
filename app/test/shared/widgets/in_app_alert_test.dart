import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/theme/bakery_theme.dart';
import 'package:bakery_app/shared/widgets/in_app_alert.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap({VoidCallback? onDismiss}) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => InAppAlert.show(
                context: context,
                count: 2,
                onDismiss: onDismiss,
              ),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

// InAppAlert schedules a 6-second auto-dismiss Future.delayed. Advance the
// fake clock past it so no timer is left pending at end-of-test.
Future<void> _drainAutoDismissTimer(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  group('InAppAlert overlay', () {
    testWidgets('renders overlay using BakeryTheme critical alert colors', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      // Material container uses the critical alert background color.
      final material = tester.widget<Material>(
        find.ancestor(
          of: find.byIcon(Icons.warning_amber_rounded),
          matching: find.byType(Material),
        ).first,
      );
      expect(material.color, BakeryTheme.criticalAlertBackground);

      // Title text uses the critical alert foreground color.
      final title = tester.widget<Text>(find.text(OrdersLabels.criticalAlertTitle));
      expect(title.style?.color, BakeryTheme.criticalAlertForeground);

      // Warning icon uses the critical alert foreground color.
      final icon = tester.widget<Icon>(find.byIcon(Icons.warning_amber_rounded));
      expect(icon.color, BakeryTheme.criticalAlertForeground);

      // Dismiss button uses the critical alert foreground color.
      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(
        button.style?.foregroundColor?.resolve({WidgetState.pressed}),
        BakeryTheme.criticalAlertForeground,
      );

      await _drainAutoDismissTimer(tester);
    });

    testWidgets('shows the critical alert body with the provided count', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.criticalAlertBody(2)), findsOneWidget);

      await _drainAutoDismissTimer(tester);
    });

    testWidgets('tapping dismiss removes the overlay and calls onDismiss', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(_wrap(onDismiss: () => dismissed = true));
      await tester.tap(find.text('trigger'));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.criticalAlertDismiss), findsOneWidget);
      await tester.tap(find.text(OrdersLabels.criticalAlertDismiss));
      await tester.pumpAndSettle();

      expect(find.text(OrdersLabels.criticalAlertTitle), findsNothing);
      expect(dismissed, isTrue);

      await _drainAutoDismissTimer(tester);
    });
  });
}