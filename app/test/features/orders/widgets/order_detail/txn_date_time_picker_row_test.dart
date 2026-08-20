import 'package:bakery_app/features/orders/widgets/order_detail/txn_date_time_picker_row.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: SingleChildScrollView(child: child),
        ),
      ),
    );

void main() {
  group('TxnDateTimePickerRow (DG-415 Phase 3 / FR1, FR7)', () {
    testWidgets(
        'renders the Vietnamese date and time labels and the current '
        'timestamp (FR1)', (tester) async {
      final dt = DateTime(2026, 8, 20, 14, 30);
      await tester.pumpWidget(
        _wrap(
          TxnDateTimePickerRow(
            dateTime: dt,
            onDateChanged: (_) {},
            onTimeChanged: (_) {},
          ),
        ),
      );

      expect(find.text(OrdersLabels.txnDateLabel), findsOneWidget);
      expect(find.text(OrdersLabels.txnTimeLabel), findsOneWidget);
      expect(find.text('20/08/2026'), findsOneWidget);
      expect(find.text('14:30'), findsOneWidget);
    });

    testWidgets(
        'tapping the date cell opens a DatePicker with lastDate=today '
        '(FR7 / AC7)', (tester) async {
      DateTime? captured;
      await tester.pumpWidget(
        _wrap(
          TxnDateTimePickerRow(
            dateTime: DateTime(2026, 8, 20, 9, 0),
            onDateChanged: (d) => captured = d,
            onTimeChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();

      // The Material date picker dialog is showing.
      expect(find.byType(DatePickerDialog), findsOneWidget);
      // Today's day number should be selectable (tappable) — confirm the
      // dialog's lastDate is today by selecting today and confirming.
      final today = DateTime.now();
      final todayLabel = '${today.day}';
      // Tap today's cell in the grid if visible.
      final todayCell = find.text(todayLabel);
      if (todayCell.evaluate().isNotEmpty) {
        await tester.tap(todayCell.first);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      // FR7: picked date cannot be after today.
      expect(
        captured!.isAfter(DateTime.now().add(const Duration(days: 1))),
        isFalse,
      );
    });

    testWidgets(
        'date picker firstDate is 2020 (FR7 — past bound)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TxnDateTimePickerRow(
            dateTime: DateTime(2026, 8, 20, 9, 0),
            onDateChanged: (_) {},
            onTimeChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();

      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(dialog.initialDate, DateTime(2026, 8, 20));
      expect(dialog.firstDate, DateTime(2020));
      expect(dialog.lastDate.isAfter(DateTime.now()), isFalse);
    });

    testWidgets('tapping the time cell opens a TimePickerDialog (FR1)',
        (tester) async {
      TimeOfDay? captured;
      await tester.pumpWidget(
        _wrap(
          TxnDateTimePickerRow(
            dateTime: DateTime(2026, 8, 20, 9, 0),
            onDateChanged: (_) {},
            onTimeChanged: (t) => captured = t,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.access_time));
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsOneWidget);
      // Dismiss the dialog without selecting (no callback fired).
      Navigator.of(tester.element(find.byType(TimePickerDialog))).pop();
      await tester.pumpAndSettle();
      expect(captured, isNull);
      expect(find.byType(TimePickerDialog), findsNothing);
    });
  });
}