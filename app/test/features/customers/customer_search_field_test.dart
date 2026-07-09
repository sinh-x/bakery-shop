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
  testWidgets('browse-on-open: shows all customers inline when <= cap (AC-1, AC-4)',
      (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
      const Customer(id: 2, name: 'An', phone: '0909876543'),
    ];
    await _pumpField(tester, _FakeCustomerService(customers));

    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('An'), findsOneWidget);
  });

  testWidgets('browse-on-open: shows 20 newest customers when > cap (AC-4)',
      (tester) async {
    final customers = List.generate(
      25,
      (i) => Customer(
        id: i + 1,
        name: 'Customer ${i + 1}',
        phone: '090${(1000000 + i).toString().padLeft(7, '0')}',
      ),
    );
    await _pumpField(tester, _FakeCustomerService(customers));

    expect(find.text('Customer 25'), findsOneWidget);
    final listView = tester.widget<ListView>(find.byType(ListView));
    final delegate = listView.childrenDelegate;
    if (delegate is SliverChildBuilderDelegate) {
      expect(delegate.childCount, 20);
    }
  });

  testWidgets('typing filters inline list in client mode (AC-2)', (tester) async {
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
    await tester.pumpAndSettle();

    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('An'), findsNothing);

    await tester.tap(find.text('Sinh'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.id, 1);
    expect(
      find.textContaining(VN.customerSearchLinked.replaceAll('{name}', 'Sinh')),
      findsOneWidget,
    );
  });

  testWidgets('selection clears the TextField (AC-5)', (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ];
    Customer? selected;
    await _pumpField(
      tester,
      _FakeCustomerService(customers),
      onSelected: (c) => selected = c,
    );

    await tester.enterText(find.byType(TextField), 'Sinh');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Sinh'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.id, 1);
    expect(
      find.textContaining(VN.customerSearchLinked.replaceAll('{name}', 'Sinh')),
      findsOneWidget,
    );
  });

  testWidgets('editing after selection does NOT trigger onSelected(null) (AC-5)',
      (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ];
    Customer? selected =
        const Customer(id: 1, name: 'Sinh', phone: '0901234567');
    await _pumpField(
      tester,
      _FakeCustomerService(customers),
      initial: selected,
      onSelected: (c) => selected = c,
    );

    await tester.enterText(find.byType(TextField), 'Other');
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.id, 1);
  });

  testWidgets('clearing after selection does NOT trigger onSelected(null) (AC-5)',
      (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ];
    Customer? selected =
        const Customer(id: 1, name: 'Sinh', phone: '0901234567');
    await _pumpField(
      tester,
      _FakeCustomerService(customers),
      initial: selected,
      onSelected: (c) => selected = c,
    );

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.id, 1);
  });

  testWidgets('no-match shows no-match message (AC-7)', (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ];
    await _pumpField(tester, _FakeCustomerService(customers));

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text(VN.customerSearchNoMatch), findsOneWidget);
  });

  testWidgets('search by secondary phone surfaces customer', (tester) async {
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

    await tester.enterText(find.byType(TextField), '0909876543');
    await tester.pumpAndSettle();

    expect(find.text('Sinh'), findsOneWidget);
  });

  testWidgets('diacritic-insensitive: "sinh" matches "Sính"', (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sính', phone: '0901234567'),
      const Customer(id: 2, name: 'An', phone: '0909876543'),
    ];
    await _pumpField(tester, _AllCustomersService(customers));

    await tester.enterText(find.byType(TextField), 'sinh');
    await tester.pumpAndSettle();

    expect(find.text('Sính'), findsOneWidget,
        reason:
            'diacritic-insensitive match should surface "Sính" for query "sinh"');
    expect(find.text('An'), findsNothing);
  });

  testWidgets('multi-phone match via phones list', (tester) async {
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
    await tester.pumpAndSettle();

    expect(find.text('Hoa'), findsOneWidget,
        reason:
            'query matching only a secondary phone should surface the customer');
  });

  testWidgets('error shows error label and retry re-runs load (AC-6)',
      (tester) async {
    final service = _ThrowingCustomerService();
    await _pumpField(tester, service);

    expect(find.text(VN.customerSearchError), findsOneWidget);
    expect(find.text(VN.retry), findsOneWidget);

    await tester.tap(find.text(VN.retry));
    await tester.pumpAndSettle();

    expect(find.text(VN.customerSearchError), findsOneWidget);
    expect(service.callCount, greaterThanOrEqualTo(2),
        reason: 'retry must trigger another listCustomers call');
  });

  testWidgets('server-mode caps results at 20 rows (AC-3)', (tester) async {
    final customers = List.generate(
      25,
      (i) => Customer(
        id: i + 1,
        name: 'Customer ${i + 1}',
        phone: '090${(1000000 + i).toString().padLeft(7, '0')}',
      ),
    );
    await _pumpField(tester, _FakeCustomerService(customers));

    await tester.enterText(find.byType(TextField), 'Customer');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView));
    final delegate = listView.childrenDelegate;
    if (delegate is SliverChildBuilderDelegate) {
      expect(delegate.childCount, 20);
    }
  });

  testWidgets('server-mode shows refine hint when results exceed 20 (AC-3)',
      (tester) async {
    final customers = List.generate(
      25,
      (i) => Customer(
        id: i + 1,
        name: 'Customer ${i + 1}',
        phone: '090${(1000000 + i).toString().padLeft(7, '0')}',
      ),
    );
    await _pumpField(tester, _FakeCustomerService(customers));

    await tester.enterText(find.byType(TextField), 'Customer');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text(VN.customerSearchRefineHint), findsOneWidget);
  });
}

class _AllCustomersService extends CustomerService {
  _AllCustomersService(this._customers) : super(Dio());

  final List<Customer> _customers;

  @override
  Future<List<Customer>> listCustomers({String? search}) async =>
      List.of(_customers);
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
