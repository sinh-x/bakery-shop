import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/orders/widgets/order_customer_section.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

void main() {
  testWidgets('OrderCustomerSection readOnly renders customer name and phone info rows',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OrderCustomerSection(
            mode: OrderCustomerSectionMode.readOnly,
            customerName: 'Nguyễn Văn A',
            customerPhone: '0987654321',
          ),
        ),
      ),
    );

    expect(find.byType(OrderCustomerSection), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('0987654321'), findsOneWidget);
  });

  testWidgets('OrderCustomerSection readOnly renders CustomerProfileCard when customer provided',
      (tester) async {
    const customer = Customer(
      id: 7,
      name: 'Trần Thị B',
      phone: '0901234567',
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: OrderCustomerSection(
              mode: OrderCustomerSectionMode.readOnly,
              selectedCustomer: customer,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Trần Thị B'), findsWidgets);
  });

  testWidgets('OrderCustomerSection editable renders name and phone text fields',
      (tester) async {
    final nameCtrl = TextEditingController(text: 'Lê Minh C');
    final phoneCtrl = TextEditingController(text: '0912345678');
    Customer? picked;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: OrderCustomerSection(
              mode: OrderCustomerSectionMode.editable,
              selectedCustomer: null,
              customerTouched: true,
              nameCtrl: nameCtrl,
              phoneCtrl: phoneCtrl,
              onSelected: (c) => picked = c,
              onClearSelection: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(OrderCustomerSection), findsOneWidget);
    expect(find.text(VN.customerName), findsOneWidget);
    expect(find.text(VN.customerPhone), findsOneWidget);
    expect(find.text('Lê Minh C'), findsOneWidget);
    expect(find.text('0912345678'), findsOneWidget);
    expect(picked, isNull);
  });
}