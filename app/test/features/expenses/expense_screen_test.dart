import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/expenses/expense_form_screen.dart';
import 'package:bakery_app/features/expenses/expense_screen.dart';
import 'package:bakery_app/features/expenses/widgets/expense_history_card.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

BakeryEvent _expenseEvent({
  required int id,
  required int amount,
  required String category,
  required String paymentMethod,
  required String staff,
  String vendor = '',
  String note = '',
  String paymentSource = 'Shop tiền mặt',
  String paidByName = '',
  String loggedBy = '',
  bool reimbursed = false,
}) {
  return BakeryEvent(
    id: id,
    timestamp: DateTime.parse('2026-05-23T10:00:00Z'),
    type: expenseType,
    summary: 'Chi phi test',
    loggedBy: loggedBy.isNotEmpty ? loggedBy : staff,
    data: {
      'amount_vnd': amount,
      'category': category,
      'payment_method': paymentMethod,
      'payment_source': paymentSource,
      'vendor': vendor,
      'note': note,
      'staff_name': staff,
      'paid_by_name': paidByName,
      'reimbursed': reimbursed,
    },
  );
}

Future<List<BakeryEvent>> _emptyHistory({
  String? since,
  String? until,
  String? category,
  String? paymentMethod,
  String? paymentSource,
  String? staffName,
  String? paidByName,
  String? loggedBy,
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
                  since,
                  until,
                  category,
                  paymentMethod,
                  paymentSource,
              staffName,
              paidByName,
              loggedBy,
              searchText,
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
    expect(capturedSince, contains('T00:00:00'));
    expect(capturedUntil, contains('T23:59:59.999'));
  });

  testWidgets('plus button opens dedicated add route', (tester) async {
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'Lan'});
    final prefs = await SharedPreferences.getInstance();

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/expenses',
          builder: (context, state) =>
              const ExpenseScreen(loadHistory: _emptyHistory),
        ),
        GoRoute(
          path: '/expenses/new',
          builder: (context, state) => const ExpenseFormScreen(),
        ),
      ],
      initialLocation: '/expenses',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text(VN.expenseAddAction), findsOneWidget);
  });

  testWidgets('edit opens dedicated form route with prepopulated data', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final event = _expenseEvent(
      id: 9,
      amount: 150000,
      category: VN.expenseCategoryIngredient,
      paymentMethod: VN.methodCash,
      vendor: 'NCC A',
      note: 'Bot mi',
      staff: 'Lan',
      paidByName: 'Lan',
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/expenses',
          builder: (context, state) => ExpenseScreen(
            loadHistory:
                ({
                  since,
                  until,
                  category,
                  paymentMethod,
                  paymentSource,
                  staffName,
                  paidByName,
                  loggedBy,
                  searchText,
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

    await tester.ensureVisible(find.text(VN.editEvent));
    await tester.tap(find.text(VN.editEvent));
    await tester.pumpAndSettle();

    expect(find.text(VN.expenseUpdateAction), findsWidgets);
    expect(find.text('150000'), findsOneWidget);
    expect(find.text('NCC A'), findsOneWidget);
    expect(find.text('Bot mi'), findsOneWidget);
  });

  testWidgets(
    'edit form stays in update mode even when legacy expense payload is partial',
    (tester) async {
      final legacyExpense = BakeryEvent(
        id: 11,
        timestamp: DateTime.parse('2026-05-23T10:00:00Z'),
        type: expenseType,
        summary: 'Chi phi cu',
        data: const {
          'category': 'Nguyên liệu',
          'payment_method': 'Tiền mặt',
          'vendor': 'NCC C',
          'note': 'Thiếu amount cũ',
          'staff_name': 'Lan',
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: ExpenseFormScreen(event: legacyExpense)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(VN.expenseUpdateAction), findsWidgets);
      expect(find.text(VN.expenseAddAction), findsNothing);
    },
  );

  testWidgets('delete shows confirmation and calls delete callback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
                  paymentSource,
                  staffName,
                  paidByName,
                  loggedBy,
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
          builder: (context, state) => ExpenseScreen(
            loadHistory:
                ({
                  since,
                  until,
                  category,
                  paymentMethod,
                  paymentSource,
                  staffName,
                  paidByName,
                  loggedBy,
                  searchText,
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
        paidByName: 'Lan',
      ),
    ];

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
                  paymentSource,
                  staffName,
                  paidByName,
                  loggedBy,
                  searchText,
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
    expect(tester.widget<FilterChip>(allChips.at(2)).selected, isTrue);
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

  testWidgets('apply filters uses category and paid_by chips', (tester) async {
    String? capturedCategory;
    String? capturedPaidByName;
    final events = [
      _expenseEvent(
        id: 1,
        amount: 120000,
        category: VN.expenseCategoryIngredient,
        paymentMethod: VN.methodCash,
        staff: 'Lan',
        paidByName: 'Lan',
      ),
    ];

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
                  paymentSource,
                  staffName,
                  paidByName,
                  loggedBy,
                  searchText,
                }) async {
                  capturedCategory = category;
                  capturedPaidByName = paidByName;
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
    expect(capturedPaidByName, 'Lan');
  });

  testWidgets('selecting category chip reloads with category filter', (
    tester,
  ) async {
    String? capturedCategory;
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
                  since,
                  until,
                  category,
                  paymentMethod,
                  paymentSource,
                  staffName,
                  paidByName,
                  loggedBy,
                  searchText,
                }) async {
                  capturedCategory = category;
                  return events;
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(VN.expenseCategoryIngredient).first);
    await tester.pumpAndSettle();

    expect(capturedCategory, VN.expenseCategoryIngredient);
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

  testWidgets('history card shows reimbursed badge when true', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final event = _expenseEvent(
      id: 1,
      amount: 120000,
      category: VN.expenseCategoryIngredient,
      paymentMethod: VN.methodCash,
      paymentSource: VN.paymentSourceStaffAdvance,
      staff: 'Lan',
      reimbursed: true,
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
                  paymentSource,
                  staffName,
                  paidByName,
                  loggedBy,
                  searchText,
                }) async => [event],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(VN.reimbursedYes), findsOneWidget);
    expect(find.text(VN.reimbursedNo), findsNothing);
  });

  testWidgets(
    'history card shows not-reimbursed badge for staff advance',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 1920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final event = _expenseEvent(
        id: 1,
        amount: 120000,
        category: VN.expenseCategoryIngredient,
        paymentMethod: VN.methodCash,
        paymentSource: VN.paymentSourceStaffAdvance,
        staff: 'Lan',
        reimbursed: false,
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
                    paymentSource,
                    staffName,
                    paidByName,
                    loggedBy,
                    searchText,
                  }) async => [event],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(VN.reimbursedNo), findsOneWidget);
      expect(find.text(VN.reimbursedYes), findsNothing);
    },
  );

  testWidgets(
    'history card shows no reimbursed badge for shop cash source',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 1920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final event = _expenseEvent(
        id: 1,
        amount: 120000,
        category: VN.expenseCategoryIngredient,
        paymentMethod: VN.methodCash,
        paymentSource: VN.paymentSourceShopCash,
        staff: 'Lan',
        reimbursed: false,
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
                    paymentSource,
                    staffName,
                    paidByName,
                    loggedBy,
                    searchText,
                  }) async => [event],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(VN.reimbursedYes), findsNothing);
      expect(find.text(VN.reimbursedNo), findsNothing);
    },
  );

  testWidgets('history card shows payment source in info line', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final event = _expenseEvent(
      id: 1,
      amount: 120000,
      category: VN.expenseCategoryIngredient,
      paymentMethod: VN.methodCash,
      paymentSource: VN.paymentSourcePhuongVCB,
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
                  paymentSource,
                  staffName,
                  paidByName,
                  loggedBy,
                  searchText,
                }) async => [event],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final infoText = find.descendant(
      of: find.byType(ExpenseHistoryCard),
      matching: find.textContaining(VN.paymentSourcePhuongVCB),
    );
    expect(infoText, findsOneWidget);
  });

  testWidgets('filter card shows payment source chips', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ExpenseScreen(loadHistory: _emptyHistory)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(VN.expensePaymentSourceLabel), findsOneWidget);
    final paymentSourceChips = find.byWidgetPredicate(
      (widget) =>
          widget is FilterChip &&
          widget.label is Text &&
          (widget.label as Text).data == VN.paymentSourceShopCash,
    );
    await tester.dragUntilVisible(
      paymentSourceChips,
      find.byType(ListView).at(1),
      const Offset(-50, 0),
    );
    expect(paymentSourceChips, findsOneWidget);
  });

  testWidgets('selecting payment source chip reloads with filter', (
    tester,
  ) async {
    String? capturedPaymentSource;
    final events = [
      _expenseEvent(
        id: 1,
        amount: 120000,
        category: VN.expenseCategoryIngredient,
        paymentMethod: VN.methodCash,
        paymentSource: VN.paymentSourcePhuongVCB,
        staff: 'Lan',
      ),
    ];

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
                  paymentSource,
                  staffName,
                  paidByName,
                  loggedBy,
                  searchText,
                }) async {
                  capturedPaymentSource = paymentSource;
                  return events;
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chip = find.byWidgetPredicate(
      (widget) =>
          widget is FilterChip &&
          widget.label is Text &&
          (widget.label as Text).data == VN.paymentSourcePhuongVCB,
    );
    await tester.dragUntilVisible(
      chip,
      find.byType(ListView).at(1),
      const Offset(-50, 0),
    );
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(capturedPaymentSource, VN.paymentSourcePhuongVCB);
  });

  testWidgets('clear filters resets payment source chip', (tester) async {
    final events = [
      _expenseEvent(
        id: 1,
        amount: 120000,
        category: VN.expenseCategoryIngredient,
        paymentMethod: VN.methodCash,
        paymentSource: VN.paymentSourcePhuongVCB,
        staff: 'Lan',
      ),
    ];

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
                  paymentSource,
                  staffName,
                  paidByName,
                  loggedBy,
                  searchText,
                }) async => events,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chip = find.byWidgetPredicate(
      (widget) =>
          widget is FilterChip &&
          widget.label is Text &&
          (widget.label as Text).data == VN.paymentSourcePhuongVCB,
    );
    await tester.dragUntilVisible(
      chip,
      find.byType(ListView).at(1),
      const Offset(-50, 0),
    );
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.expenseResetFiltersAction));
    await tester.pumpAndSettle();

    final allChips = find.widgetWithText(FilterChip, VN.filterAll);
    expect(tester.widget<FilterChip>(allChips.at(1)).selected, isTrue);
  });

  testWidgets('form screen shows payment source dropdown', (tester) async {
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'Lan'});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: ExpenseFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(VN.expensePaymentSourceLabel), findsOneWidget);
    expect(find.text(VN.paymentSourceShopCash), findsOneWidget);
  });

  testWidgets('history card shows logged_by and paid_by roles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final event = BakeryEvent(
      id: 1,
      timestamp: DateTime.parse('2026-05-23T10:00:00Z'),
      type: expenseType,
      summary: 'Chi phi test',
      loggedBy: 'Sinh',
      data: {
        'amount_vnd': 120000,
        'category': VN.expenseCategoryIngredient,
        'payment_method': VN.methodCash,
        'payment_source': VN.paymentSourceShopCash,
        'vendor': '',
        'note': '',
        'staff_name': 'Lan',
        'paid_by_name': 'Minh',
        'reimbursed': false,
      },
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
                  paymentSource,
                  staffName,
                  paidByName,
                  loggedBy,
                  searchText,
                }) async => [event],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('${VN.expenseLoggedByLabel}: Sinh'), findsOneWidget);
    expect(find.textContaining('${VN.expensePaidByNameLabel}: Minh'), findsOneWidget);
  });

  testWidgets('history card shows fallback for missing paid_by_name', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final event = _expenseEvent(
      id: 1,
      amount: 120000,
      category: VN.expenseCategoryIngredient,
      paymentMethod: VN.methodCash,
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
                  paymentSource,
                  staffName,
                  paidByName,
                  loggedBy,
                  searchText,
                }) async => [event],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('${VN.expensePaidByNameLabel}: Lan'), findsOneWidget);
  });
}
