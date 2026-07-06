import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/customers/customer_detail_screen.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCustomerService extends CustomerService {
  _FakeCustomerService(this._customer, this._orders)
      : super(Dio());

  final Customer _customer;
  final List<Map<String, dynamic>> _orders;

  @override
  Future<Customer> getCustomer(int id) async => _customer;

  @override
  Future<List<Map<String, dynamic>>> getCustomerOrders(int id) async =>
      _orders;
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
        home: const CustomerDetailScreen(customerId: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'detail card shows all phones with primary highlighted (AC9)',
      (tester) async {
    const customer = Customer(
      id: 1,
      name: 'Sinh',
      phone: '0901234567',
      phones: [
        CustomerPhone(phone: '0901234567', isPrimary: true),
        CustomerPhone(phone: '0909876543', isPrimary: false),
      ],
    );
    await _pumpScreen(tester, _FakeCustomerService(customer, const []));

    // Both phone numbers should appear.
    expect(find.textContaining('0901234567'), findsOneWidget);
    expect(find.textContaining('0909876543'), findsOneWidget);
    // The primary phone label marker should appear once.
    expect(find.textContaining(VN.customerPrimaryPhone), findsOneWidget);
  });

  testWidgets(
      'detail card falls back to legacy phone when phones list empty',
      (tester) async {
    const customer =
        Customer(id: 1, name: 'Sinh', phone: '0901234567');
    await _pumpScreen(tester, _FakeCustomerService(customer, const []));

    expect(find.textContaining('0901234567'), findsOneWidget);
    // No "(Số chính)" marker is appended in legacy fallback mode.
    expect(find.textContaining(VN.customerPrimaryPhone), findsNothing);
  });

  testWidgets('detail card shows no phone line when customer has none',
      (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '');
    await _pumpScreen(tester, _FakeCustomerService(customer, const []));

    expect(find.text('Sinh'), findsOneWidget);
    // No star icons (phone lines) should be rendered.
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.star_border), findsNothing);
  });
}