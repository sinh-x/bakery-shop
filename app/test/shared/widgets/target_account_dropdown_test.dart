import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/shared/widgets/target_account_dropdown.dart';
import 'package:bakery_app/shared/labels/expenses.dart';

void main() {
  group('TargetAccountDropdown (DG-281 Phase 3)', () {
    Widget buildDropdown({
      String? value,
      ValueChanged<String?>? onChanged,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: TargetAccountDropdown(
            value: value,
            onChanged: onChanged,
          ),
        ),
      );
    }

    testWidgets(
        'FR4: null value displays "Chưa chọn" (no selection)',
        (tester) async {
      await tester.pumpWidget(buildDropdown());
      await tester.pumpAndSettle();

      expect(find.text(ExpensesLabels.paymentNoAccount), findsOneWidget);
      final dropdown = tester.widget<DropdownButtonFormField<String?>>(
        find.byType(DropdownButtonFormField<String?>),
      );
      expect(dropdown.initialValue, isNull);
    });

    testWidgets(
        'FR2: non-null value displays the selected bank account name',
        (tester) async {
      await tester.pumpWidget(
        buildDropdown(value: ExpensesLabels.paymentSourcePhuongVCB),
      );
      await tester.pumpAndSettle();

      expect(find.text(ExpensesLabels.paymentSourcePhuongVCB), findsOneWidget);
      final dropdown = tester.widget<DropdownButtonFormField<String?>>(
        find.byType(DropdownButtonFormField<String?>),
      );
      expect(dropdown.initialValue, ExpensesLabels.paymentSourcePhuongVCB);
    });

    testWidgets('value change on rebuild updates the dropdown selection',
        (tester) async {
      await tester.pumpWidget(buildDropdown(value: ExpensesLabels.paymentSourcePhuongVCB));
      await tester.pumpAndSettle();

      expect(find.text(ExpensesLabels.paymentSourcePhuongVCB), findsOneWidget);

      await tester.pumpWidget(buildDropdown(value: ExpensesLabels.paymentSourceAnVCB));
      await tester.pumpAndSettle();

      expect(find.text(ExpensesLabels.paymentSourceAnVCB), findsOneWidget);
      final dropdown = tester.widget<DropdownButtonFormField<String?>>(
        find.byType(DropdownButtonFormField<String?>),
      );
      expect(dropdown.initialValue, ExpensesLabels.paymentSourceAnVCB);
    });

    testWidgets('selecting an account fires onChanged with the value',
        (tester) async {
      String? captured;
      await tester.pumpWidget(
        buildDropdown(onChanged: (v) => captured = v),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ExpensesLabels.paymentSourceAnVCB).last);
      await tester.pumpAndSettle();

      expect(captured, ExpensesLabels.paymentSourceAnVCB);
    });
  });
}