import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/orders/widgets/order_payment_section.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/utils.dart';

void main() {
  testWidgets('OrderPaymentSection readOnly renders unpaid status when nothing paid',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrderPaymentSection(
            amountPaid: 0,
            totalPrice: 100000,
            paymentMethod: 'cash',
          ),
        ),
      ),
    );

    expect(find.byType(OrderPaymentSection), findsOneWidget);
    expect(find.text(OrdersLabels.payment), findsWidgets);
    expect(find.text(OrdersLabels.unpaid), findsOneWidget);
    expect(find.text(OrdersLabels.methodCash), findsOneWidget);
    expect(find.text(formatVND(0)), findsOneWidget);
    expect(find.text(formatVND(100000)), findsOneWidget);
  });

  testWidgets('OrderPaymentSection shows paid status when fully paid',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrderPaymentSection(
            amountPaid: 150000,
            totalPrice: 150000,
            paymentMethod: 'transfer',
          ),
        ),
      ),
    );

    expect(find.text(OrdersLabels.paid), findsOneWidget);
    expect(find.text(OrdersLabels.methodTransfer), findsOneWidget);
  });

  testWidgets('OrderPaymentSection editable shows add-payment button when remaining > 0',
      (tester) async {
    var addPressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderPaymentSection(
            amountPaid: 50000,
            totalPrice: 200000,
            mode: OrderPaymentSectionMode.editable,
            onAddPayment: () => addPressed = true,
          ),
        ),
      ),
    );

    expect(find.text(OrdersLabels.partialPaid), findsOneWidget);
    final button = find.byType(OutlinedButton);
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(addPressed, isTrue);
  });
}