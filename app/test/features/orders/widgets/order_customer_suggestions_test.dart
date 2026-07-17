import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/orders/widgets/order_customer_suggestions.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCustomerService extends CustomerService {
  _FakeCustomerService(this._customers) : super(Dio());

  final List<Customer> _customers;

  @override
  Future<List<Customer>> listCustomers({String? search}) async {
    if (search == null || search.trim().isEmpty) return List.of(_customers);
    final q = search.trim().toLowerCase();
    return _customers
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.phone.contains(q) ||
              c.phones.any((p) => p.phone.contains(q)),
        )
        .toList();
  }
}

class _RecordingCustomerService extends CustomerService {
  _RecordingCustomerService(this._customers) : super(Dio());

  final List<Customer> _customers;
  final List<String> calls = [];

  @override
  Future<List<Customer>> listCustomers({String? search}) async {
    calls.add(search ?? '');
    if (search == null || search.trim().isEmpty) return List.of(_customers);
    final q = search.trim().toLowerCase();
    return _customers
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.phone.contains(q) ||
              c.phones.any((p) => p.phone.contains(q)),
        )
        .toList();
  }
}

class _ThrowingCustomerService extends CustomerService {
  _ThrowingCustomerService() : super(Dio());
  int callCount = 0;

  @override
  Future<List<Customer>> listCustomers({String? search}) async {
    callCount++;
    throw Exception('search failed (test)');
  }
}

Future<void> _pump(
  WidgetTester tester,
  CustomerService service, {
  TextEditingController? nameCtrl,
  TextEditingController? phoneCtrl,
  Customer? selected,
  ValueChanged<Customer>? onSelected,
}) async {
  final name = nameCtrl ?? TextEditingController();
  final phone = phoneCtrl ?? TextEditingController();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [customerServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: name),
                TextField(controller: phone),
                OrderCustomerSuggestions(
                  nameCtrl: name,
                  phoneCtrl: phone,
                  onSelected: onSelected ?? (_) {},
                  selectedCustomer: selected,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Finder scoped to suggestion ListTiles (excludes the EditableText in the
/// name/phone input fields).
Finder _suggestion(String text) => find.widgetWithText(ListTile, text);

void main() {
  testWidgets('does not show suggestions when query < 2 chars (FR4)', (tester) async {
    final svc = _RecordingCustomerService([
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ]);
    await _pump(tester, svc);

    await tester.enterText(find.byType(TextField).first, 'S');
    await tester.pumpAndSettle();

    expect(_suggestion('Sinh'), findsNothing);
    expect(svc.calls, isEmpty,
        reason: 'no search should fire for < 2 chars');
  });

  testWidgets('shows matching customer after typing ≥2 chars and debounce (FR4, NFR4)',
      (tester) async {
    final svc = _RecordingCustomerService([
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
      const Customer(id: 2, name: 'An', phone: '0909876543'),
    ]);
    await _pump(tester, svc);

    await tester.enterText(find.byType(TextField).first, 'Sin');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(_suggestion('Sinh'), findsOneWidget);
    expect(_suggestion('An'), findsNothing);
    expect(svc.calls, contains('Sin'));
  });

  testWidgets('tapping a suggestion calls onSelected (tap-to-link, FR4, AC2)',
      (tester) async {
    Customer? picked;
    await _pump(
      tester,
      _FakeCustomerService([
        const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
      ]),
      onSelected: (c) => picked = c,
    );

    await tester.enterText(find.byType(TextField).first, 'Sin');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(_suggestion('Sinh'), findsOneWidget);

    await tester.tap(_suggestion('Sinh'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.id, 1);
  });

  testWidgets('debounce 350ms: no search fires before the window elapses (NFR4)',
      (tester) async {
    final svc = _RecordingCustomerService([
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ]);
    await _pump(tester, svc);

    await tester.enterText(find.byType(TextField).first, 'Sin');
    await tester.pump(const Duration(milliseconds: 349));

    expect(svc.calls, isEmpty,
        reason: 'search must not fire before 350ms debounce window');

    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();

    expect(svc.calls, contains('Sin'),
        reason: 'search fires after the 350ms window elapses');
  });

  testWidgets('caps results at 10 rows and shows refine hint (NFR4)', (tester) async {
    final customers = List.generate(
      15,
      (i) => Customer(
        id: i + 1,
        name: 'Customer ${i + 1}',
        phone: '090${(1000000 + i).toString().padLeft(7, '0')}',
      ),
    );
    await _pump(tester, _FakeCustomerService(customers));

    await tester.enterText(find.byType(TextField).first, 'Customer');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNWidgets(CustomersLabels.orderSuggestionsCap),
        reason: 'NFR4: results capped at 10 rows');
    expect(find.text(CustomersLabels.orderSuggestionsRefineHint),
        findsOneWidget,
        reason: 'refine hint shown when results exceed cap');
  });

  testWidgets('phone field drives suggestions when longer than name', (tester) async {
    final svc = _RecordingCustomerService([
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ]);
    await _pump(tester, svc);

    await tester.enterText(find.byType(TextField).last, '0901');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(_suggestion('Sinh'), findsOneWidget);
    expect(svc.calls, contains('0901'));
  });

  testWidgets('hides suggestions when query drops below 2 chars', (tester) async {
    await _pump(
      tester,
      _FakeCustomerService([
        const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
      ]),
    );

    await tester.enterText(find.byType(TextField).first, 'Sin');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(_suggestion('Sinh'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'S');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(_suggestion('Sinh'), findsNothing,
        reason: '< 2 chars should clear suggestions');
  });

  testWidgets('hides suggestions when selected customer matches the query (AC2)',
      (tester) async {
    final svc = _RecordingCustomerService([
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ]);
    await _pump(
      tester,
      svc,
      selected: const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    );

    await tester.enterText(find.byType(TextField).first, 'Sinh');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(_suggestion('Sinh'), findsNothing,
        reason: 'selected customer already matches; do not re-prompt');
    expect(svc.calls, isEmpty);
  });

  testWidgets('shows error view on failure and retry re-runs search', (tester) async {
    final svc = _ThrowingCustomerService();
    await _pump(tester, svc);

    await tester.enterText(find.byType(TextField).first, 'Sin');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text(CustomersLabels.orderSuggestionsError), findsOneWidget);
    expect(find.text(CustomersLabels.orderSuggestionsRetry), findsOneWidget);

    await tester.tap(find.text(CustomersLabels.orderSuggestionsRetry));
    await tester.pumpAndSettle();

    expect(svc.callCount, greaterThanOrEqualTo(2));
  });
}