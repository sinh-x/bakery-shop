import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/orders/widgets/order_delivery_section.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

void main() {
  testWidgets('OrderDeliverySection readOnly pickup renders only delivery type row',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrderDeliverySection(
            deliveryType: 'pickup',
            shippingFee: 0,
          ),
        ),
      ),
    );

    expect(find.byType(OrderDeliverySection), findsOneWidget);
    expect(find.text(VN.pickup), findsOneWidget);
    expect(find.text(VN.deliveryAddress), findsNothing);
  });

  testWidgets('OrderDeliverySection readOnly door renders address, phone, shipping fee',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrderDeliverySection(
            deliveryType: 'door',
            deliveryAddress: '123 Lê Lợi',
            customerPhone: '0987654321',
            shippingFee: 25000,
            notes: 'Giao trước 9h',
          ),
        ),
      ),
    );

    expect(find.text(VN.deliveryDoor), findsOneWidget);
    expect(find.text('123 Lê Lợi'), findsOneWidget);
    expect(find.text('0987654321'), findsOneWidget);
    expect(find.text(formatVND(25000)), findsOneWidget);
    expect(find.text('Giao trước 9h'), findsOneWidget);
  });

  testWidgets('OrderDeliverySection editable renders delivery type segmented button',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderDeliverySection(
            deliveryType: 'pickup',
            mode: OrderDeliverySectionMode.editable,
            onDeliveryTypeChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.text(VN.pickup), findsOneWidget);
    expect(find.text(VN.deliveryBus), findsOneWidget);
    expect(find.text(VN.deliveryDoor), findsOneWidget);
  });

  testWidgets('OrderDeliverySection editable door shows address field and shipping stepper',
      (tester) async {
    final addressCtrl = TextEditingController(text: '45 Trần Phú');
    final phoneCtrl = TextEditingController(text: '0901234567');
    double? fee;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderDeliverySection(
            deliveryType: 'door',
            mode: OrderDeliverySectionMode.editable,
            addressCtrl: addressCtrl,
            phoneCtrl: phoneCtrl,
            shippingFee: 20000,
            onShippingFeeChanged: (v) => fee = v,
          ),
        ),
      ),
    );

    expect(find.text(VN.deliveryAddress), findsOneWidget);
    expect(find.text('45 Trần Phú'), findsOneWidget);
    expect(find.text('0901234567'), findsOneWidget);
    expect(find.text(formatVND(20000)), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pump();
    expect(fee, 25000);
  });
}