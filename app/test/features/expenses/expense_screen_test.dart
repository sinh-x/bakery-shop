import 'package:bakery_app/features/expenses/expense_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('invalid amount blocks save and shows Vietnamese validation', (
    tester,
  ) async {
    var saveCalled = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ExpenseScreen(
            saveExpense: (_) async {
              saveCalled += 1;
            },
            loadHistory:
                ({
                  String? since,
                  String? until,
                  String? category,
                  String? paymentMethod,
                  String? staffName,
                  String? searchText,
                }) async => const [],
          ),
        ),
      ),
    );

    await tester.tap(find.text(VN.expenseSaveAction));
    await tester.pumpAndSettle();

    expect(find.text(VN.expenseAmountValidationMessage), findsOneWidget);
    expect(saveCalled, 0);
  });
}
