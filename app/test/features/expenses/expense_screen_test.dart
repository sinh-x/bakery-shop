import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/expenses/expense_form_screen.dart';
import 'package:bakery_app/features/expenses/expense_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
  testWidgets('default list loads with initial 7-day date range', (
    tester,
  ) async {
    String? capturedSince;
    String? capturedUntil;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ExpenseScreen(
            loadHistory:
                ({
                  String? since,
                  String? until,
                  String? category,
                  String? paymentMethod,
                  String? staffName,
                  String? searchText,
                }) async {
                  capturedSince = since;
                  capturedUntil = until;
                  return const [];
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(capturedSince, isNotNull);
    expect(capturedUntil, isNotNull);
  });

  testWidgets('plus button opens dedicated add route', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/expenses',
          builder: (_, __) => const ExpenseScreen(loadHistory: _emptyHistory),
        ),
        GoRoute(
          path: '/expenses/new',
          builder: (_, __) => const ExpenseFormScreen(),
        ),
      ],
      initialLocation: '/expenses',
    );

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text(VN.expenseAddAction), findsOneWidget);
  });

  testWidgets('edit opens dedicated form route with prepopulated data', (
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

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/expenses',
          builder: (_, __) => ExpenseScreen(
            loadHistory:
                ({
                  String? since,
                  String? until,
                  String? category,
                  String? paymentMethod,
                  String? staffName,
                  String? searchText,
                }) async => [event],
          ),
        ),
        GoRoute(
          path: '/expenses/:id/edit',
          builder: (_, state) =>
              ExpenseFormScreen(event: state.extra as BakeryEvent),
        ),
      ],
      initialLocation: '/expenses',
    );

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(VN.editEvent));
    await tester.pumpAndSettle();

    expect(find.text(VN.expenseUpdateAction), findsOneWidget);
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

  testWidgets('returning true from add route refreshes list', (tester) async {
    var loads = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/expenses',
          builder: (_, __) => ExpenseScreen(
            loadHistory:
                ({
                  String? since,
                  String? until,
                  String? category,
                  String? paymentMethod,
                  String? staffName,
                  String? searchText,
                }) async {
                  loads += 1;
                  return const [];
                },
          ),
        ),
        GoRoute(
          path: '/expenses/new',
          builder: (context, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.pop(true),
                child: const Text('done'),
              ),
            ),
          ),
        ),
      ],
      initialLocation: '/expenses',
    );

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    final before = loads;

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('done'));
    await tester.pumpAndSettle();

    expect(loads, greaterThan(before));
  });

  testWidgets('clear filters resets search and staff fields', (tester) async {
    final events = [
      _expenseEvent(
        id: 1,
        amount: 120000,
        category: VN.expenseCategoryIngredient,
        paymentMethod: VN.methodCash,
        staff: 'Lan',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ExpenseScreen(
            loadHistory:
                ({
                  String? since,
                  String? until,
                  String? category,
                  String? paymentMethod,
                  String? staffName,
                  String? searchText,
                }) async => events,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'bot');
    await tester.tap(find.text(VN.expenseCategoryIngredient).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lan').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.expenseResetFiltersAction));
    await tester.pumpAndSettle();

    expect(find.text('bot'), findsNothing);
    final allChips = find.widgetWithText(FilterChip, VN.filterAll);
    expect(tester.widget<FilterChip>(allChips.at(0)).selected, isTrue);
    expect(tester.widget<FilterChip>(allChips.at(1)).selected, isTrue);
  });

  testWidgets('filter card uses chips and hides payment method filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ExpenseScreen(loadHistory: _emptyHistory)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(ChoiceChip, VN.lichSuDonHangLocMotNgay),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(ChoiceChip, VN.lichSuDonHangLocKhoangNgay),
      findsOneWidget,
    );
    expect(find.text(VN.expensePaymentMethodLabel), findsNothing);
  });

  testWidgets('apply filters uses category and staff chips', (tester) async {
    String? capturedCategory;
    String? capturedStaff;
    final events = [
      _expenseEvent(
        id: 1,
        amount: 120000,
        category: VN.expenseCategoryIngredient,
        paymentMethod: VN.methodCash,
        staff: 'Lan',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ExpenseScreen(
            loadHistory:
                ({
                  String? since,
                  String? until,
                  String? category,
                  String? paymentMethod,
                  String? staffName,
                  String? searchText,
                }) async {
                  capturedCategory = category;
                  capturedStaff = staffName;
                  return events;
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(VN.expenseCategoryIngredient).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lan').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.expenseApplyFiltersAction));
    await tester.pumpAndSettle();

    expect(capturedCategory, VN.expenseCategoryIngredient);
    expect(capturedStaff, 'Lan');
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
