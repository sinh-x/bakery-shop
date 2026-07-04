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

  testWidgets('clear button resets selection and calls onSelected with null',
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

    expect(find.byTooltip(VN.customerSearchClear), findsOneWidget);

    await tester.tap(find.byTooltip(VN.customerSearchClear));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.byType(TextField), findsWidgets);
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
}