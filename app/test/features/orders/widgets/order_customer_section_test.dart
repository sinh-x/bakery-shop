import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/orders/widgets/order_customer_section.dart';
import 'package:bakery_app/shared/labels/orders.dart';

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

  testWidgets(
      'OrderCustomerSection editable renders the "Tìm khách hàng" button and name/phone text fields (FR-8)',
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
    // The search entry is now a button, not an inline text field.
    expect(find.text(OrdersLabels.customerSearchButton), findsOneWidget);
    expect(find.text(VN.customerName), findsOneWidget);
    expect(find.text(VN.customerPhone), findsOneWidget);
    expect(find.text('Lê Minh C'), findsOneWidget);
    expect(find.text('0912345678'), findsOneWidget);
    expect(picked, isNull);
  });

  testWidgets('tapping the search button opens the customer search modal (FR-8, AC7)',
      (tester) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: OrderCustomerSection(
              mode: OrderCustomerSectionMode.editable,
              selectedCustomer: null,
              nameCtrl: nameCtrl,
              phoneCtrl: phoneCtrl,
              onSelected: (_) {},
              onClearSelection: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text(OrdersLabels.customerSearchButton));
    await tester.pumpAndSettle();

    // Modal title + hosted search field render.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(OrdersLabels.customerSearchModalTitle),
      ),
      findsOneWidget,
    );
    // The name/phone input fields remain separate from the modal search entry.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(VN.customerName),
      ),
      findsNothing,
      reason: 'AC7: name/phone fields should remain outside the search modal',
    );
  });

  testWidgets('tapping (x) on linked customer card calls onClearSelection (unlinks) (AC4)',
      (tester) async {
    const customer = Customer(
      id: 9,
      name: 'Phạm Văn D',
      phone: '0901234567',
    );
    final nameCtrl = TextEditingController(text: 'Phạm Văn D');
    final phoneCtrl = TextEditingController(text: '0901234567');
    var cleared = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: OrderCustomerSection(
              mode: OrderCustomerSectionMode.editable,
              selectedCustomer: customer,
              nameCtrl: nameCtrl,
              phoneCtrl: phoneCtrl,
              onClearSelection: () => cleared = true,
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip(VN.customerSearchClear), findsOneWidget);

    await tester.tap(find.byTooltip(VN.customerSearchClear));
    await tester.pumpAndSettle();

    expect(cleared, isTrue);
  });

  testWidgets('tapping (x) clears name and phone TextFormField values (AC4)',
      (tester) async {
    const customer = Customer(
      id: 9,
      name: 'Phạm Văn D',
      phone: '0901234567',
    );
    final nameCtrl = TextEditingController(text: 'Phạm Văn D');
    final phoneCtrl = TextEditingController(text: '0901234567');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: OrderCustomerSection(
              mode: OrderCustomerSectionMode.editable,
              selectedCustomer: customer,
              nameCtrl: nameCtrl,
              phoneCtrl: phoneCtrl,
              onClearSelection: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip(VN.customerSearchClear));
    await tester.pumpAndSettle();

    expect(nameCtrl.text, '');
    expect(phoneCtrl.text, '');
  });
}