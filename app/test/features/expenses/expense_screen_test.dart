import 'package:bakery_app/features/expenses/expense_screen.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

BakeryEvent _expenseEvent({
  required int id,
  required int amount,
  required String category,
  required String paymentMethod,
  required String staff,
  String vendor = '',
  String note = '',
}) {
  return BakeryEvent(
    id: id,
    timestamp: DateTime.parse('2026-05-23T10:00:00Z'),
    type: expenseType,
    summary: 'Chi phi test',
    data: {
      'amount_vnd': amount,
      'category': category,
      'payment_method': paymentMethod,
      'vendor': vendor,
      'note': note,
      'staff_name': staff,
    },
  );
}

Future<List<BakeryEvent>> _emptyHistory({
  String? since,
  String? until,
  String? category,
  String? paymentMethod,
  String? staffName,
  String? searchText,
}) async => const [];

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
            loadHistory: _emptyHistory,
          ),
        ),
      ),
    );

    await tester.tap(find.text(VN.expenseSaveAction));
    await tester.pumpAndSettle();

    expect(find.text(VN.expenseAmountValidationMessage), findsOneWidget);
    expect(saveCalled, 0);
  });

  testWidgets('save success calls callback and keeps snackbar flow stable', (
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
            loadHistory: _emptyHistory,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, '120000');
    await tester.tap(find.text(VN.expenseSaveAction));
    await tester.pumpAndSettle();

    expect(saveCalled, 1);
  });

  testWidgets('edit prepopulates form from selected history item', (
    tester,
  ) async {
    final event = _expenseEvent(
      id: 9,
      amount: 150000,
      category: VN.expenseCategoryIngredient,
      paymentMethod: VN.methodCash,
      vendor: 'NCC A',
      note: 'Bot mi',
      staff: 'Lan',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ExpenseScreen(
            loadHistory:
                ({
                  since,
                  until,
                  category,
                  paymentMethod,
                  staffName,
                  searchText,
                }) async => [event],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(VN.editEvent));
    await tester.pumpAndSettle();

    expect(find.text('150000'), findsOneWidget);
    expect(find.text('NCC A'), findsOneWidget);
    expect(find.text('Bot mi'), findsOneWidget);
    expect(find.text('Lan'), findsOneWidget);
  });

  testWidgets('delete shows confirmation and calls delete callback', (
    tester,
  ) async {
    var deletedId = -1;
    final event = _expenseEvent(
      id: 3,
      amount: 20000,
      category: VN.expenseCategoryOther,
      paymentMethod: VN.methodCash,
      staff: 'Minh',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ExpenseScreen(
            deleteExpense: (id) async {
              deletedId = id;
            },
            loadHistory:
                ({
                  since,
                  until,
                  category,
                  paymentMethod,
                  staffName,
                  searchText,
                }) async => [event],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(VN.deleteEvent).first);
    await tester.pumpAndSettle();
    expect(find.text(VN.deleteEventConfirm), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, VN.deleteEvent));
    await tester.pumpAndSettle();

    expect(deletedId, 3);
  });

  testWidgets('renders history item details from expense data', (tester) async {
    final event = _expenseEvent(
      id: 4,
      amount: 30000,
      category: VN.expenseCategoryDelivery,
      paymentMethod: VN.methodTransfer,
      vendor: 'NCC B',
      note: 'Ship',
      staff: 'Hoa',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ExpenseScreen(
            loadHistory:
                ({
                  since,
                  until,
                  category,
                  paymentMethod,
                  staffName,
                  searchText,
                }) async => [event],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(VN.expenseCategoryDelivery), findsOneWidget);
    expect(find.textContaining(VN.methodTransfer), findsOneWidget);
    expect(find.textContaining('Hoa'), findsOneWidget);
    expect(find.textContaining('NCC B'), findsOneWidget);
    expect(find.textContaining('Ship'), findsOneWidget);
  });

  testWidgets('clear filters resets search and staff fields', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ExpenseScreen(loadHistory: _emptyHistory)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'bot');
    await tester.enterText(find.byType(TextField).at(1), 'Lan');
    await tester.tap(find.text(VN.expenseResetFiltersAction));
    await tester.pumpAndSettle();

    expect(find.text('bot'), findsNothing);
    expect(find.text('Lan'), findsNothing);
  });

  testWidgets('shows empty history state when no expense item', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ExpenseScreen(loadHistory: _emptyHistory)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(VN.expenseNoHistory), findsOneWidget);
  });
}
