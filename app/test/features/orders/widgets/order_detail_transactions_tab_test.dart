import 'package:bakery_app/data/models/payment_transaction.dart';
import 'package:bakery_app/data/models/order_photo.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_detail_transactions_tab.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_payment_history.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_photo_thumbnail.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

Order _order({double totalPrice = 500000, double shippingFee = 0}) =>
    Order.fromJson({
      'id': '1',
      'orderRef': 'ORD-1',
      'status': 'new',
      'customerName': 'KH A',
      'customerPhone': '',
      'dueDate': null,
      'dueTime': '10:00',
      'deliveryType': 'pickup',
      'deliveryAddress': '',
      'items': <Map<String, dynamic>>[
        {'productId': 'p', 'productName': 'Bánh kem', 'quantity': 1, 'unitPrice': totalPrice},
      ],
      'totalPrice': totalPrice,
      'amountPaid': 0.0,
      'isPaid': false,
      'notes': '',
      'source': '',
      'packingChecklist': <dynamic>[],
      'shippingFee': shippingFee,
      'workTicketPrintedAt': null,
      'createdBy': '',
      'createdAt': '2026-08-07T08:00:00Z',
      'updatedAt': '2026-08-07T08:00:00Z',
      'completeness': 'complete',
      'missingFields': <String>[],
    });

PaymentTransaction _txn({String id = '1', double amount = 100000}) =>
    PaymentTransaction(
      id: id,
      orderId: '1',
      amount: amount,
      type: 'deposit',
      method: 'cash',
      createdAt: DateTime.parse('2026-08-07T09:00:00Z'),
    );

Future<void> _pump(
  WidgetTester tester, {
  required Order order,
  required double amountPaid,
  required double remaining,
  List<PaymentTransaction> txns = const [],
  List<OrderPhoto> transferPhotos = const [],
  String baseUrl = 'http://test',
  VoidCallback? onAddPayment,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: OrderDetailTransactionsTab(
          order: order,
          amountPaid: amountPaid,
          remaining: remaining,
          txns: txns,
          onAddPayment: onAddPayment ?? () {},
          onTransactionTap: (_) {},
          transferPhotos: transferPhotos,
          baseUrl: baseUrl,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'renders payment summary: total, paid, remaining (FR6/AC5)',
      (tester) async {
    // totalPrice = 500000, amountPaid = 200000 → remaining = 300000.
    await _pump(
      tester,
      order: _order(totalPrice: 500000),
      amountPaid: 200000,
      remaining: 300000,
    );

    expect(find.text(VN.total), findsOneWidget);
    expect(find.text('500.000đ'), findsOneWidget);
    expect(find.text(VN.amountPaidLabel), findsOneWidget);
    expect(find.text('200.000đ'), findsOneWidget);
    expect(find.text(VN.remainingLabel), findsOneWidget);
    expect(find.text('300.000đ'), findsOneWidget);
  });

  testWidgets(
      'renders "Thêm giao dịch" button that invokes onAddPayment (FR5/AC4)',
      (tester) async {
    var tapped = 0;
    await _pump(
      tester,
      order: _order(),
      amountPaid: 0,
      remaining: 500000,
      onAddPayment: () => tapped++,
    );

    final button = find.text(VN.orderDetailAddTransaction);
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('renders the payment history list below the summary',
      (tester) async {
    final txns = [_txn(id: '1', amount: 100000), _txn(id: '2', amount: 50000)];
    await _pump(
      tester,
      order: _order(totalPrice: 500000),
      amountPaid: 150000,
      remaining: 350000,
      txns: txns,
    );

    expect(find.byType(OrderPaymentHistory), findsOneWidget);
    // Summary still rendered above the history.
    expect(find.text('500.000đ'), findsOneWidget);
    expect(find.text('150.000đ'), findsOneWidget);
    expect(find.text('350.000đ'), findsOneWidget);
  });

  testWidgets('shows zero remaining when balance is settled', (tester) async {
    await _pump(
      tester,
      order: _order(totalPrice: 500000),
      amountPaid: 500000,
      remaining: 0,
    );

    // Total + paid both show 500.000đ; remaining shows 0đ.
    expect(find.text('500.000đ'), findsNWidgets(2));
    expect(find.text('0đ'), findsOneWidget);
  });

  testWidgets(
      'renders transfer photo section with thumbnails and tag chips when '
      'chuyen-khoan photos are provided (FR1/AC1)', (tester) async {
    final photos = [
      const OrderPhoto(
        id: 10,
        orderId: 1,
        photoHash: 'hashA',
        tags: 'chuyen-khoan',
      ),
      const OrderPhoto(
        id: 11,
        orderId: 1,
        photoHash: 'hashB',
        tags: 'chuyen-khoan',
      ),
    ];
    await _pump(
      tester,
      order: _order(totalPrice: 500000),
      amountPaid: 100000,
      remaining: 400000,
      transferPhotos: photos,
    );

    // Section header.
    expect(find.text(VN.transferPhotosSection), findsOneWidget);
    // Two thumbnails rendered.
    expect(find.byType(OrderPhotoThumbnail), findsNWidgets(2));
    // The "Chuyển khoản" tag chip label (from kOrderPhotoTags) is rendered
    // for both photos.
    expect(find.text('Chuyển khoản'), findsNWidgets(2));
  });

  testWidgets(
      'renders empty-state hint when no chuyen-khoan photos are provided '
      '(FR1/AC1)', (tester) async {
    await _pump(
      tester,
      order: _order(totalPrice: 500000),
      amountPaid: 100000,
      remaining: 400000,
      transferPhotos: const [],
    );

    expect(find.text(VN.transferPhotosSection), findsOneWidget);
    expect(find.text(VN.noTransferPhotos), findsOneWidget);
    expect(find.byType(OrderPhotoThumbnail), findsNothing);
  });
}