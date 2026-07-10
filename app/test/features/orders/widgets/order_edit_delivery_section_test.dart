import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/orders/widgets/hour_picker.dart';
import 'package:bakery_app/features/orders/widgets/order_delivery_section.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/utils/phone_formatter.dart';

// DG-216 Phase 3: the order edit screen's Stage 3 delivery UI now renders the
// canonical shared [OrderDeliverySection] in editable mode, preserving the
// edit-specific due date/time controls (HourPresetChips) via the composable
// `dueDateTimeSlot` and the delivery-phone [PhoneInputFormatter] via
// `phoneInputFormatters`. These tests exercise that exact configuration.

Widget _editStage3Delivery({
  required String deliveryType,
  required TextEditingController addressCtrl,
  required TextEditingController phoneCtrl,
  required TextEditingController notesCtrl,
  ValueChanged<TimeOfDay>? onPresetSelected,
  TimeOfDay? dueTime,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: OrderDeliverySection(
          mode: OrderDeliverySectionMode.editable,
          deliveryType: deliveryType,
          shippingFee: 20000,
          addressCtrl: addressCtrl,
          phoneCtrl: phoneCtrl,
          phoneInputFormatters: [PhoneInputFormatter()],
          notesCtrl: notesCtrl,
          onDeliveryTypeChanged: (_) {},
          onShippingFeeChanged: (_) {},
          dueTime: dueTime,
          dueDateTimeSlot: HourPresetChips(
            selectedTime: dueTime,
            onSelected: onPresetSelected ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'edit Stage 3 renders OrderDeliverySection in editable mode',
      (tester) async {
    await tester.pumpWidget(_editStage3Delivery(
      deliveryType: 'door',
      addressCtrl: TextEditingController(),
      phoneCtrl: TextEditingController(),
      notesCtrl: TextEditingController(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(OrderDeliverySection), findsOneWidget);
    // Editable mode shows the delivery type segmented selector.
    expect(find.text(VN.deliveryType), findsOneWidget);
    expect(find.text(VN.pickup), findsWidgets);
  });

  testWidgets('edit Stage 3 delivery fields are editable', (tester) async {
    final addressCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    await tester.pumpWidget(_editStage3Delivery(
      deliveryType: 'door',
      addressCtrl: addressCtrl,
      phoneCtrl: phoneCtrl,
      notesCtrl: notesCtrl,
    ));
    await tester.pumpAndSettle();

    // Address, delivery phone, and notes fields all render and accept input.
    expect(find.text(VN.deliveryAddress), findsOneWidget);
    expect(find.text(OrdersLabels.deliveryPhone), findsOneWidget);
    expect(find.text(VN.notes), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, VN.deliveryAddress),
      '12 Lê Lợi',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, VN.notes),
      'Giao buổi sáng',
    );
    expect(addressCtrl.text, '12 Lê Lợi');
    expect(notesCtrl.text, 'Giao buổi sáng');
  });

  testWidgets('edit Stage 3 applies PhoneInputFormatter to delivery phone',
      (tester) async {
    final phoneCtrl = TextEditingController();

    await tester.pumpWidget(_editStage3Delivery(
      deliveryType: 'door',
      addressCtrl: TextEditingController(),
      phoneCtrl: phoneCtrl,
      notesCtrl: TextEditingController(),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, OrdersLabels.deliveryPhone),
      '0912345678',
    );
    // PhoneInputFormatter formats 10 digits as xxxx-xxx-xxx.
    expect(phoneCtrl.text, '0912-345-678');
  });

  testWidgets('edit Stage 3 preserves HourPresetChips via dueDateTimeSlot',
      (tester) async {
    TimeOfDay? selected;

    await tester.pumpWidget(_editStage3Delivery(
      deliveryType: 'pickup',
      addressCtrl: TextEditingController(),
      phoneCtrl: TextEditingController(),
      notesCtrl: TextEditingController(),
      onPresetSelected: (t) => selected = t,
    ));
    await tester.pumpAndSettle();

    // The due date section renders the edit-specific preset chips.
    expect(find.byType(HourPresetChips), findsOneWidget);
    expect(find.text(VN.dueDate), findsWidgets);

    // The default DueDateTimePickerRow is NOT used (replaced by the slot).
    expect(find.text(OrdersLabels.notSelected), findsNothing);

    // Tapping a preset chip fires the callback with the expected time slot.
    await tester.tap(find.text('${VN.timeSlotMorning} 8:00'));
    await tester.pump();
    expect(selected, const TimeOfDay(hour: 8, minute: 0));
  });
}
