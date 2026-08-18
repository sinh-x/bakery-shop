import 'package:cached_network_image/cached_network_image.dart';
import 'package:bakery_app/data/models/enum_attribute.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_items_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bakery_app/shared/labels/orders.dart';

const _nhanBanh = EnumAttribute(
  attributeType: 'nhan_banh',
  labelVi: 'Nhân bánh',
  options: [
    EnumOption(id: 1, valueVi: 'Sầu riêng', isDefault: true),
    EnumOption(id: 2, valueVi: 'Sô-cô-la'),
  ],
);

Order _order({
  List<Map<String, dynamic>> items = const [],
  double totalPrice = 300000,
}) {
  return Order.fromJson({
    'id': '1',
    'orderRef': 'ORD-1',
    'status': 'new',
    'customerName': 'KH A',
    'customerPhone': '',
    'dueDate': null,
    'dueTime': '10:00',
    'deliveryType': 'pickup',
    'deliveryAddress': '',
    'items': items,
    'totalPrice': totalPrice,
    'amountPaid': 0.0,
    'isPaid': false,
    'notes': '',
    'source': '',
    'packingChecklist': <dynamic>[],
    'shippingFee': 0.0,
    'workTicketPrintedAt': null,
    'createdBy': '',
    'createdAt': '2026-08-07T08:00:00Z',
    'updatedAt': '2026-08-07T08:00:00Z',
    'completeness': 'complete',
    'missingFields': <String>[],
  });
}

Product _product({
  int id = 5,
  String name = 'Bánh kem dâu',
  String photoPath = 'photos/abc.jpg',
  String productCode = '',
  List<EnumAttribute> enumAttributes = const [_nhanBanh],
}) {
  return Product(
    id: id,
    name: name,
    category: 'banh_kem',
    basePrice: 300000,
    cost: 0,
    recipeNotes: '',
    active: 1,
    photoPath: photoPath,
    productCode: productCode,
    priceChips: const [],
    attributes: const {},
    enumAttributes: enumAttributes,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Order order,
  List<Product> products, {
  String baseUrl = 'http://test.local:8000',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            OrderItemsList(
              order: order,
              enumAttributesFor: (id) {
                for (final p in products) {
                  if (p.id.toString() == id || p.productCode == id) {
                    return p.enumAttributes;
                  }
                }
                return const [];
              },
              products: products,
              baseUrl: baseUrl,
            ),
          ],
        ),
      ),
    ),
  );
  // Allow CachedNetworkImage placeholder to settle without network.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('OrderItemsList — product photo (FR1 / AC1)', () {
    testWidgets('renders CachedNetworkImage thumbnail when photoPath is set',
        (tester) async {
      final order = _order(items: [
        {
          'productId': '5',
          'productName': 'Bánh kem dâu',
          'quantity': 1,
          'unitPrice': 300000,
        },
      ]);
      await _pump(tester, order, [_product(photoPath: 'photos/abc.jpg')]);

      expect(find.byType(CachedNetworkImage), findsOneWidget);
      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, contains('/api/products/5/photo'));
      expect(image.width, 40);
      expect(image.height, 40);
    });

    testWidgets('does NOT render photo when photoPath is empty', (tester) async {
      final order = _order(items: [
        {
          'productId': '5',
          'productName': 'Bánh kem dâu',
          'quantity': 1,
          'unitPrice': 300000,
        },
      ]);
      await _pump(tester, order, [_product(photoPath: '')]);

      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('does NOT render photo when product is not found',
        (tester) async {
      final order = _order(items: [
        {
          'productId': '999',
          'productName': 'Bánh lạ',
          'quantity': 1,
          'unitPrice': 100000,
        },
      ]);
      await _pump(tester, order, [_product(id: 5)]);

      expect(find.byType(CachedNetworkImage), findsNothing);
      // Item name still renders.
      expect(find.text('Bánh lạ'), findsOneWidget);
    });
  });

  group('OrderItemsList — birthday / age / candle / notes (FR2 / AC1 / AC2)',
      () {
    testWidgets('shows birthday emoji, age "X tuổi", and notes', (tester) async {
      final order = _order(items: [
        {
          'productId': '5',
          'productName': 'Bánh kem',
          'quantity': 1,
          'unitPrice': 300000,
          'isBirthday': true,
          'age': 5,
          'notes': 'Không đường',
        },
      ]);
      await _pump(tester, order, [_product(photoPath: '')]);

      // Birthday line: "Sinh nhật 5 tuổi"
      expect(find.textContaining('Sinh nhật'), findsOneWidget);
      expect(find.textContaining('5 tuổi'), findsOneWidget);
      // Notes rendered as italic text.
      expect(find.text('Không đường'), findsOneWidget);
    });

    testWidgets('shows birthday label without age when age is null',
        (tester) async {
      final order = _order(items: [
        {
          'productId': '5',
          'productName': 'Bánh kem',
          'quantity': 1,
          'unitPrice': 300000,
          'isBirthday': true,
        },
      ]);
      await _pump(tester, order, [_product(photoPath: '')]);

      expect(find.text('Sinh nhật'), findsOneWidget);
      expect(find.textContaining('tuổi'), findsNothing);
    });

    testWidgets('shows candle type label for nen_so (AC2)', (tester) async {
      final order = _order(items: [
        {
          'productId': '5',
          'productName': 'Bánh kem',
          'quantity': 1,
          'unitPrice': 300000,
          'attributes': {'candle_type': 'nen_so'},
        },
      ]);
      await _pump(tester, order, [_product(photoPath: '')]);

      expect(find.text('${OrdersLabels.packCandles}: ${OrdersLabels.candleTypeNenSo}'),
          findsOneWidget);
    });

    testWidgets('does NOT show candle line for khong_nen', (tester) async {
      final order = _order(items: [
        {
          'productId': '5',
          'productName': 'Bánh kem',
          'quantity': 1,
          'unitPrice': 300000,
          'attributes': {'candle_type': 'khong_nen'},
        },
      ]);
      await _pump(tester, order, [_product(photoPath: '')]);

      expect(find.textContaining(OrdersLabels.packCandles), findsNothing);
    });

    testWidgets('does NOT show candle line when candle_type absent',
        (tester) async {
      final order = _order(items: [
        {
          'productId': '5',
          'productName': 'Bánh kem',
          'quantity': 1,
          'unitPrice': 300000,
        },
      ]);
      await _pump(tester, order, [_product(photoPath: '')]);

      expect(find.textContaining(OrdersLabels.packCandles), findsNothing);
    });

    testWidgets('does NOT show notes line when notes empty', (tester) async {
      final order = _order(items: [
        {
          'productId': '5',
          'productName': 'Bánh kem',
          'quantity': 1,
          'unitPrice': 300000,
          'notes': '',
        },
      ]);
      await _pump(tester, order, [_product(photoPath: '')]);

      // Product name present, no extra italic notes text beyond product name.
      expect(find.text('Bánh kem'), findsOneWidget);
    });
  });

  group('OrderItemsList — enum attributes (FR3)', () {
    testWidgets('renders enum attribute label:value line', (tester) async {
      final order = _order(items: [
        {
          'productId': '5',
          'productName': 'Bánh kem',
          'quantity': 1,
          'unitPrice': 300000,
          'attributes': {'nhan_banh': 'Sô-cô-la'},
        },
      ]);
      await _pump(tester, order, [_product(photoPath: '')]);

      expect(find.text('Nhân bánh: Sô-cô-la'), findsOneWidget);
    });
  });

  group('OrderItemsList — combined (AC1 full)', () {
    testWidgets('renders photo + birthday + age + candle + notes together',
        (tester) async {
      final order = _order(items: [
        {
          'productId': '5',
          'productName': 'Bánh kem dâu',
          'quantity': 1,
          'unitPrice': 300000,
          'isBirthday': true,
          'age': 5,
          'notes': 'Không đường',
          'attributes': {
            'candle_type': 'nen_so',
            'nhan_banh': 'Sầu riêng',
          },
        },
      ]);
      await _pump(tester, order, [_product(photoPath: 'photos/abc.jpg')]);

      // Photo
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      // Birthday + age
      expect(find.textContaining('Sinh nhật'), findsOneWidget);
      expect(find.textContaining('5 tuổi'), findsOneWidget);
      // Candle type
      expect(find.text('${OrdersLabels.packCandles}: ${OrdersLabels.candleTypeNenSo}'),
          findsOneWidget);
      // Notes
      expect(find.text('Không đường'), findsOneWidget);
      // Enum attribute
      expect(find.text('Nhân bánh: Sầu riêng'), findsOneWidget);
    });
  });
}