import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/customers/widgets/customer_search_field.dart';
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
    // Match against name, primary phone, or any entry in the phones list
    // (mirrors the backend search that joins customer_phones).
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

Future<void> _pumpField(
  WidgetTester tester,
  CustomerService service, {
  Customer? initial,
  ValueChanged<Customer?>? onSelected,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [customerServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: CustomerSearchField(
            initialCustomer: initial,
            onSelected: onSelected,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('typing a partial query shows matching suggestions', (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
      const Customer(id: 2, name: 'An', phone: '0909876543'),
    ];
    Customer? selected;
    await _pumpField(
      tester,
      _FakeCustomerService(customers),
      onSelected: (c) => selected = c,
    );

    await tester.enterText(find.byType(TextField), 'Sin');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Sinh'), findsWidgets);
    expect(find.text('An'), findsNothing);

    await tester.tap(find.text('Sinh'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.id, 1);
    expect(find.textContaining(VN.customerSearchLinked.replaceAll('{name}', 'Sinh')),
        findsOneWidget);
  });

  testWidgets('tapping a result clears the TextField instead of displaying the customer name (AC5)',
      (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ];
    Customer? selected;
    await _pumpField(
      tester,
      _FakeCustomerService(customers),
      onSelected: (c) => selected = c,
    );

    await tester.enterText(find.byType(TextField), 'Sin');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sinh'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.id, 1);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, '');
  });

  testWidgets('editing search text after selecting does NOT trigger onSelected(null) (AC3)',
      (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ];
    Customer? selected = const Customer(id: 1, name: 'Sinh', phone: '0901234567');
    await _pumpField(
      tester,
      _FakeCustomerService(customers),
      initial: selected,
      onSelected: (c) => selected = c,
    );

    await tester.enterText(find.byType(TextField), 'Other');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.id, 1);
  });

  testWidgets('clearing search text after selecting does NOT trigger onSelected(null) (AC3)',
      (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ];
    Customer? selected = const Customer(id: 1, name: 'Sinh', phone: '0901234567');
    await _pumpField(
      tester,
      _FakeCustomerService(customers),
      initial: selected,
      onSelected: (c) => selected = c,
    );

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.id, 1);
  });

  testWidgets('empty query does not trigger a search overlay', (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ];
    await _pumpField(tester, _FakeCustomerService(customers));

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text(VN.customerSearchNoMatch), findsNothing);
  });

  testWidgets('no-match query shows the no-match message', (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ];
    await _pumpField(tester, _FakeCustomerService(customers));

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text(VN.customerSearchNoMatch), findsOneWidget);
  });

  // AC10 — searching by a secondary phone surfaces the matching customer.
  testWidgets('search by secondary phone surfaces matching customer (AC10)',
      (tester) async {
    final customers = [
      const Customer(
        id: 1,
        name: 'Sinh',
        phone: '0901234567',
        phones: [
          CustomerPhone(phone: '0901234567', isPrimary: true),
          CustomerPhone(phone: '0909876543', isPrimary: false),
        ],
      ),
    ];
    await _pumpField(tester, _FakeCustomerService(customers));

    // Search by the secondary phone (not the primary phone field).
    await tester.enterText(find.byType(TextField), '0909876543');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Sinh'), findsOneWidget);
  });

  // CQ-4 — diacritic-insensitive name matching: querying without diacritics
  // still surfaces a customer whose name has Vietnamese diacritics. Uses a
  // service that returns all candidates so the client-side
  // `_matchesDiacriticAware` filter performs the diacritic-stripped match.
  testWidgets(
      'diacritic-insensitive name match: query "sinh" matches "Sính" (CQ-4)',
      (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sính', phone: '0901234567'),
      const Customer(id: 2, name: 'An', phone: '0909876543'),
    ];
    await _pumpField(tester, _AllCustomersService(customers));

    await tester.enterText(find.byType(TextField), 'sinh');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Sính'), findsOneWidget,
        reason: 'CQ-4: diacritic-insensitive match should surface "Sính" for query "sinh"');
    expect(find.text('An'), findsNothing);
  });

  // CQ-4 — multi-phone matching: a query that matches a secondary phone in
  // the `phones` list (but not the primary `phone` field) still surfaces the
  // customer. Uses the all-customers service so the client-side filter's
  // `phones`-list matching is what surfaces the customer.
  testWidgets('multi-phone match via phones list (CQ-4)', (tester) async {
    final customers = [
      const Customer(
        id: 1,
        name: 'Hoa',
        phone: '0901000000',
        phones: [
          CustomerPhone(phone: '0901000000', isPrimary: true),
          CustomerPhone(phone: '0912345678', isPrimary: false),
        ],
      ),
    ];
    await _pumpField(tester, _AllCustomersService(customers));

    await tester.enterText(find.byType(TextField), '0912345678');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Hoa'), findsOneWidget,
        reason: 'CQ-4: a query matching only a secondary phone should surface the customer');
  });

  // CQ-4 — error/retry path: when the service throws, the error label and
  // retry button render, and tapping retry re-runs the search.
  testWidgets('service error shows error label and retry triggers re-search (CQ-4)',
      (tester) async {
    final service = _ThrowingCustomerService();
    await _pumpField(tester, service);

    await tester.enterText(find.byType(TextField), 'anything');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text(VN.customerSearchError), findsOneWidget,
        reason: 'CQ-4: error label should render when the search service throws');
    expect(find.text(VN.retry), findsOneWidget,
        reason: 'CQ-4: retry button should render on search error');

    // Tap retry — the search runs again (it throws again, but the important
    // assertion is that the retry callback is wired and re-enters _search).
    await tester.tap(find.text(VN.retry));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text(VN.customerSearchError), findsOneWidget,
        reason: 'CQ-4: retry should re-run the search (still erroring here)');
    expect(service.callCount, greaterThanOrEqualTo(2),
        reason: 'CQ-4: retry must trigger another listCustomers call');
  });
}

/// Returns all candidates regardless of query so the client-side
/// `_matchesDiacriticAware` filter performs the diacritic / phone-list
/// matching under test (CQ-4).
class _AllCustomersService extends CustomerService {
  _AllCustomersService(this._customers) : super(Dio());

  final List<Customer> _customers;

  @override
  Future<List<Customer>> listCustomers({String? search}) async =>
      List.of(_customers);
}

/// CustomerService whose `listCustomers` always throws, for the error/retry
/// test (CQ-4). Tracks call count so the retry assertion can confirm the
/// search was re-run.
class _ThrowingCustomerService extends CustomerService {
  _ThrowingCustomerService() : super(Dio());
  int callCount = 0;

  @override
  Future<List<Customer>> listCustomers({String? search}) async {
    callCount++;
    throw Exception('search failed (CQ-4 test)');
  }
}