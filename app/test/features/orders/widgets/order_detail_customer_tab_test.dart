import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/data/models/order_photo.dart';
import 'package:bakery_app/features/orders/widgets/order_card.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_detail_customer_tab.dart';
import 'package:bakery_app/providers/order/order_photo_providers.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake [OrderPhotosNotifier] returning an empty photo list so `OrderCard`
/// doesn't trigger a Dio request for order photos. Pattern lifted from
/// `order_card_test.dart`'s `_FakeOrderPhotosNotifier`.
class _FakeOrderPhotosNotifier extends OrderPhotosNotifier {
  _FakeOrderPhotosNotifier(this._photos, String ref) : super(ref);

  final List<OrderPhoto> _photos;

  @override
  Future<List<OrderPhoto>> build() async => _photos;
}

/// Fake [CustomerService] returning canned customer + order-history data.
///
/// Mirrors the pattern in `customer_detail_screen_test.dart`: subclasses
/// `CustomerService` and overrides the two methods the customer tab reads so
/// the tab can be pumped without a live Dio instance.
class _FakeCustomerService extends CustomerService {
  _FakeCustomerService(this._customer, this._orders) : super(Dio());

  final Customer? _customer;
  final List<Map<String, dynamic>> _orders;

  @override
  Future<Customer> getCustomer(int id) async {
    final c = _customer;
    if (c == null) throw Exception('customer not found');
    return c;
  }

  @override
  Future<List<Map<String, dynamic>>> getCustomerOrders(int id) async =>
      _orders;
}

Customer _customer({
  String name = 'Nguyễn Văn A',
  String phone = '0901234567',
  DateTime? createdAt,
}) =>
    Customer(
      id: 42,
      name: name,
      phone: phone,
      phones: const [CustomerPhone(phone: '0901234567', isPrimary: true)],
      createdAt: createdAt ?? DateTime(2026, 1, 15),
    );

Map<String, dynamic> _orderJson({
  String orderRef = 'ORD-100',
  String customerName = 'Nguyễn Văn A',
  double totalPrice = 250000,
}) =>
    {
      'id': '100',
      'orderRef': orderRef,
      'status': 'completed',
      'customerName': customerName,
      'customerPhone': '0901234567',
      'dueDate': null,
      'dueTime': null,
      'deliveryType': 'pickup',
      'deliveryAddress': '',
      'items': <Map<String, dynamic>>[
        {'productId': 'p', 'productName': 'Bánh kem', 'quantity': 1, 'unitPrice': totalPrice},
      ],
      'totalPrice': totalPrice,
      'amountPaid': totalPrice,
      'isPaid': true,
      'notes': '',
      'source': '',
      'packingChecklist': <dynamic>[],
      'shippingFee': 0.0,
      'workTicketPrintedAt': null,
      'createdBy': '',
      'createdAt': '2026-01-10T08:00:00Z',
      'updatedAt': '2026-01-10T08:00:00Z',
      'completeness': 'complete',
      'missingFields': <String>[],
    };

Future<void> _pump(
  WidgetTester tester,
  CustomerService service, {
  int? customerId,
  List<String> orderRefs = const [],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final photoOverrides = [
    for (final ref in orderRefs)
      orderPhotosProvider(ref)
          .overrideWith(() => _FakeOrderPhotosNotifier(const [], ref)),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        customerServiceProvider.overrideWithValue(service),
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...photoOverrides,
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: OrderDetailCustomerTab(customerId: customerId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'shows customer info (name, phone, created date) when customerId present (FR8/AC7)',
      (tester) async {
    final service =
        _FakeCustomerService(_customer(createdAt: DateTime(2026, 1, 15)), const []);
    await _pump(tester, service, customerId: 42);

    expect(find.text(VN.orderDetailCustomerInfoTitle), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('0901234567 (Số chính)'), findsOneWidget);
    // createdAt rendered via formatDisplayDate → "15/01/2026".
    expect(find.textContaining(VN.customerCreatedAt), findsOneWidget);
    expect(find.textContaining('15/01/2026'), findsOneWidget);
  });

  testWidgets(
      'shows order history using OrderCard when customerId present (FR9/AC7)',
      (tester) async {
    final service = _FakeCustomerService(
      _customer(),
      [_orderJson(orderRef: 'ORD-100'), _orderJson(orderRef: 'ORD-101')],
    );
    await _pump(
      tester,
      service,
      customerId: 42,
      orderRefs: const ['ORD-100', 'ORD-101'],
    );

    expect(find.text(VN.customerOrderHistory), findsOneWidget);
    // Two OrderCard widgets — one per historical order.
    expect(find.byType(OrderCard), findsNWidgets(2));
    expect(find.text('ORD-100'), findsOneWidget);
    expect(find.text('ORD-101'), findsOneWidget);
  });

  testWidgets(
      'shows "Chưa có đơn hàng" when customer has no order history',
      (tester) async {
    final service = _FakeCustomerService(_customer(), const []);
    await _pump(tester, service, customerId: 42);

    expect(find.text(VN.customerNoOrders), findsOneWidget);
    expect(find.byType(OrderCard), findsNothing);
  });

  testWidgets(
      'shows "Chưa có khách hàng" empty state when customerId is null (FR10/AC8)',
      (tester) async {
    // Service is never called when customerId is null, but pass one anyway
    // so the override is wired for the ProviderScope.
    final service = _FakeCustomerService(_customer(), const []);
    await _pump(tester, service, customerId: null);

    expect(find.text(VN.orderDetailCustomerEmpty), findsOneWidget);
    expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
    // No customer info or order history sections rendered.
    expect(find.text(VN.orderDetailCustomerInfoTitle), findsNothing);
    expect(find.text(VN.customerOrderHistory), findsNothing);
  });

  testWidgets('shows error state with retry when customer fetch fails',
      (tester) async {
    final service = _FakeCustomerService(null, const []);
    await _pump(tester, service, customerId: 42);

    expect(find.text(VN.apiError), findsOneWidget);
    expect(find.text(VN.retry), findsOneWidget);
  });
}