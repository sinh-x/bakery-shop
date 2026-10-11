import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:bakery_app/data/api/address_service.dart';
import 'package:bakery_app/data/models/address.dart';
import 'package:bakery_app/features/orders/widgets/address_autocomplete_field.dart';
import 'package:bakery_app/features/orders/widgets/order_edit/edit_stage3_delivery.dart';
import 'package:bakery_app/features/orders/widgets/order_wizard.dart';
import 'package:bakery_app/providers/address/address_autocomplete_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/orders/widgets/hour_picker.dart';
import 'package:bakery_app/features/orders/widgets/order_delivery_section.dart';
import 'package:bakery_app/shared/labels/orders.dart';

// DG-216 Phase 3 / DG-251 Phase 2: the order edit screen's Stage 3 delivery UI
// renders the canonical shared [OrderDeliverySection] in editable mode, which
// now uses the shared [PhoneTextField] for the delivery phone (formatter is
// built into the widget, so no `phoneInputFormatters` passthrough is needed).
// These tests exercise that exact configuration.

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

class _EditAddresses extends AddressService {
  _EditAddresses() : super(Dio());
  int calls = 0;
  @override
  Future<AddressAutocompleteResponse> autocomplete({
    required String query,
    int? customerId,
  }) async {
    calls++;
    return const AddressAutocompleteResponse(
      pastOrders: [
        AddressSuggestion(
          displayAddress: '12 Linked',
          googleMapsUrl: 'https://maps.example/linked',
        ),
      ],
      library: [AddressSuggestion(displayAddress: '12 Linkless')],
    );
  }
}

void main() {
  for (final type in ['bus', 'door']) {
    testWidgets(
      'DG-438 EditStage3Delivery $type forwards each exact selection once',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final address = TextEditingController();
        final phone = TextEditingController();
        final notes = TextEditingController();
        addTearDown(address.dispose);
        addTearDown(phone.dispose);
        addTearDown(notes.dispose);
        final selected = <AddressSuggestion>[];
        final service = _EditAddresses();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [addressServiceProvider.overrideWithValue(service)],
            child: MaterialApp(
              home: Scaffold(
                body: EditStage3Delivery(
                  deliveryType: type,
                  shippingFee: 20000,
                  addressCtrl: address,
                  deliveryPhoneCtrl: phone,
                  customerPhone: '',
                  notesCtrl: notes,
                  shippingBusDefault: 25000,
                  shippingDoorDefault: 20000,
                  onDeliveryTypeChanged: (_) {},
                  onShippingFeeChanged: (_) {},
                  dueDate: null,
                  dueTime: null,
                  onPickDate: () {},
                  onPickTime: () {},
                  onDueTimeChanged: (_) {},
                  wizardSnapshot: OrderWizardData(deliveryType: type),
                  summaryItems: const [],
                  onBack: () {},
                  onContinue: () {},
                  onAddressSelected: selected.add,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final field = find.descendant(
          of: find.byType(AddressAutocompleteField),
          matching: find.byType(TextFormField),
        );
        for (final text in ['12 Linked', '12 Linkless']) {
          await tester.enterText(field, '12');
          await tester.pump(kAddressAutocompleteDebounce);
          await tester.pumpAndSettle();
          final requestsBeforeSelection = service.calls;
          await tester.tap(find.text(text).last);
          await tester.pumpAndSettle();
          expect(service.calls, requestsBeforeSelection);
          expect(address.text, text);
        }
        expect(selected.map((s) => s.displayAddress), [
          '12 Linked',
          '12 Linkless',
        ]);
        expect(selected.map((s) => s.googleMapsUrl), [
          'https://maps.example/linked',
          null,
        ]);
        expect(service.calls, 1, reason: 'same query/customer reuses cache');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('edit Stage 3 renders OrderDeliverySection in editable mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _editStage3Delivery(
        deliveryType: 'door',
        addressCtrl: TextEditingController(),
        phoneCtrl: TextEditingController(),
        notesCtrl: TextEditingController(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OrderDeliverySection), findsOneWidget);
    // Editable mode shows the delivery type segmented selector.
    expect(find.text(OrdersLabels.deliveryType), findsOneWidget);
    expect(find.text(OrdersLabels.pickup), findsWidgets);
  });

  testWidgets('edit Stage 3 delivery fields are editable', (tester) async {
    final addressCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    await tester.pumpWidget(
      _editStage3Delivery(
        deliveryType: 'door',
        addressCtrl: addressCtrl,
        phoneCtrl: phoneCtrl,
        notesCtrl: notesCtrl,
      ),
    );
    await tester.pumpAndSettle();

    // Address, delivery phone, and notes fields all render and accept input.
    expect(find.text(OrdersLabels.deliveryAddress), findsOneWidget);
    expect(find.text(OrdersLabels.deliveryPhone), findsOneWidget);
    expect(find.text(OrdersLabels.notes), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, OrdersLabels.deliveryAddress),
      '12 Lê Lợi',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, OrdersLabels.notes),
      'Giao buổi sáng',
    );
    expect(addressCtrl.text, '12 Lê Lợi');
    expect(notesCtrl.text, 'Giao buổi sáng');
  });

  testWidgets('edit Stage 3 applies PhoneInputFormatter to delivery phone', (
    tester,
  ) async {
    final phoneCtrl = TextEditingController();

    await tester.pumpWidget(
      _editStage3Delivery(
        deliveryType: 'door',
        addressCtrl: TextEditingController(),
        phoneCtrl: phoneCtrl,
        notesCtrl: TextEditingController(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, OrdersLabels.deliveryPhone),
      '0912345678',
    );
    // PhoneInputFormatter formats 10 digits as xxxx-xxx-xxx.
    expect(phoneCtrl.text, '0912-345-678');
  });

  testWidgets('edit Stage 3 preserves HourPresetChips via dueDateTimeSlot', (
    tester,
  ) async {
    TimeOfDay? selected;

    await tester.pumpWidget(
      _editStage3Delivery(
        deliveryType: 'pickup',
        addressCtrl: TextEditingController(),
        phoneCtrl: TextEditingController(),
        notesCtrl: TextEditingController(),
        onPresetSelected: (t) => selected = t,
      ),
    );
    await tester.pumpAndSettle();

    // The due date section renders the edit-specific preset chips.
    expect(find.byType(HourPresetChips), findsOneWidget);
    expect(find.text(OrdersLabels.dueDate), findsWidgets);

    // The default DueDateTimePickerRow is NOT used (replaced by the slot).
    expect(find.text(OrdersLabels.notSelected), findsNothing);

    // Tapping a preset chip fires the callback with the expected time slot.
    await tester.tap(find.text('${OrdersLabels.timeSlotMorning} 8:00'));
    await tester.pump();
    expect(selected, const TimeOfDay(hour: 8, minute: 0));
  });
}
