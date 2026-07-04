import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/customers/customer_list_screen.dart';
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
          (c) => c.name.toLowerCase().contains(q) || c.phone.contains(q),
        )
        .toList();
  }
}

Future<void> _pumpScreen(
  WidgetTester tester,
  CustomerService service,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [customerServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const CustomerListScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders customers and shows empty state', (tester) async {
    await _pumpScreen(tester, _FakeCustomerService(const []));
    expect(find.text(VN.noCustomers), findsOneWidget);
  });

  testWidgets('lists customers with name and phone', (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
      const Customer(id: 2, name: 'An', phone: '0909876543'),
    ];
    await _pumpScreen(tester, _FakeCustomerService(customers));

    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('An'), findsOneWidget);
    expect(find.textContaining('0901234567'), findsOneWidget);
  });

  testWidgets('search filters customers by name', (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
      const Customer(id: 2, name: 'An', phone: '0909876543'),
    ];
    await _pumpScreen(tester, _FakeCustomerService(customers));

    await tester.enterText(find.byType(TextField), 'Sin');
    await tester.pumpAndSettle();

    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('An'), findsNothing);
  });

  testWidgets('search filters customers by phone', (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
      const Customer(id: 2, name: 'An', phone: '0909876543'),
    ];
    await _pumpScreen(tester, _FakeCustomerService(customers));

    await tester.enterText(find.byType(TextField), '765');
    await tester.pumpAndSettle();

    expect(find.text('Sinh'), findsNothing);
    expect(find.text('An'), findsOneWidget);
  });

  testWidgets('list tile shows primary phone from phones list', (tester) async {
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
    await _pumpScreen(tester, _FakeCustomerService(customers));

    // The primary phone should be shown in the subtitle; the secondary phone
    // should NOT appear in the list tile (only on the detail screen).
    expect(find.textContaining('0901234567'), findsOneWidget);
    expect(find.textContaining('0909876543'), findsNothing);
  });

  testWidgets('list tile falls back to legacy phone field when phones empty',
      (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ];
    await _pumpScreen(tester, _FakeCustomerService(customers));

    expect(find.textContaining('0901234567'), findsOneWidget);
  });
}