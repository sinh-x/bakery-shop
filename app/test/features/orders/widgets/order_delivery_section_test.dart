import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/orders/widgets/due_date_time_picker_row.dart';
import 'package:bakery_app/features/orders/widgets/order_delivery_section.dart';
import 'package:bakery_app/features/orders/widgets/stage1_responsive_content.dart';
import 'package:bakery_app/shared/labels/orders.dart';
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

  testWidgets('readOnly mode renders due date and time when provided',
      (tester) async {
    final dueDate = DateTime(2026, 7, 8);
    const dueTime = TimeOfDay(hour: 14, minute: 30);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderDeliverySection(
            deliveryType: 'door',
            deliveryAddress: '123 Lê Lợi',
            dueDate: dueDate,
            dueTime: dueTime,
          ),
        ),
      ),
    );

    expect(find.text('8/7/2026'), findsOneWidget);
    expect(find.text('14:30'), findsOneWidget);
  });

  testWidgets('editable mode renders DueDateTimePickerRow',
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

    expect(find.byType(DueDateTimePickerRow), findsOneWidget);
    expect(find.text(VN.dueDate), findsOneWidget);
    expect(find.text(OrdersLabels.notSelected), findsWidgets);
  });

  testWidgets('editable mode renders summary card slots when provided',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderDeliverySection(
            deliveryType: 'pickup',
            mode: OrderDeliverySectionMode.editable,
            onDeliveryTypeChanged: (_) {},
            summaryCardSlots: [
              const Card(child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Summary Slot Content'),
              )),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Summary Slot Content'), findsOneWidget);
  });

  testWidgets('shipping fee config loading shows spinner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderDeliverySection(
            deliveryType: 'door',
            mode: OrderDeliverySectionMode.editable,
            onDeliveryTypeChanged: (_) {},
            onShippingFeeChanged: (_) {},
            addressCtrl: TextEditingController(text: '123 Test'),
            shippingFee: 25000,
            shippingFeeConfigLoading: true,
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shipping fee config error shows retry button', (tester) async {
    var retryCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderDeliverySection(
            deliveryType: 'door',
            mode: OrderDeliverySectionMode.editable,
            onDeliveryTypeChanged: (_) {},
            onShippingFeeChanged: (_) {},
            addressCtrl: TextEditingController(text: '123 Test'),
            shippingFee: 25000,
            shippingFeeConfigError: 'Test error',
            onRetryShippingFeeConfig: () => retryCalled = true,
          ),
        ),
      ),
    );

    expect(find.text(VN.errorLoading), findsOneWidget);
    expect(find.text(VN.retry), findsOneWidget);
    await tester.tap(find.text(VN.retry));
    expect(retryCalled, true);
  });

  testWidgets('responsive layout wraps content with Stage1ResponsiveContent',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderDeliverySection(
            deliveryType: 'pickup',
            mode: OrderDeliverySectionMode.editable,
            onDeliveryTypeChanged: (_) {},
            useResponsiveLayout: true,
          ),
        ),
      ),
    );

    expect(find.byType(Stage1ResponsiveContent), findsOneWidget);
  });

  testWidgets('non-responsive layout does not add wrapper', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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

    expect(find.byType(Stage1ResponsiveContent), findsNothing);
  });
}
