import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/orders/widgets/order_delivery_section.dart';
import 'package:bakery_app/features/orders/widgets/stage1_responsive_content.dart';
import 'package:bakery_app/features/orders/widgets/stage3_delivery_options_screen.dart';
import 'package:bakery_app/features/orders/widgets/order_wizard.dart';
import 'package:bakery_app/providers/config_provider.dart';
import 'package:bakery_app/providers/order/order_create_state_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class _FixedStateNotifier extends OrderCreateStateNotifier {
  final OrderCreateState initial;
  _FixedStateNotifier(this.initial);

  @override
  OrderCreateState build() => initial;
}

class _DataConfigNotifier extends ConfigValuesNotifier {
  final List<String> _values;
  _DataConfigNotifier(this._values) : super('test');

  @override
  Future<List<String>> build() async => _values;
}

class _LoadingConfigNotifier extends ConfigValuesNotifier {
  _LoadingConfigNotifier() : super('test');

  @override
  Future<List<String>> build() => Completer<List<String>>().future;
}

class _ErrorConfigNotifier extends ConfigValuesNotifier {
  _ErrorConfigNotifier() : super('test');

  @override
  Future<List<String>> build() async => throw Exception('config load failed');
}

Widget _harness(
  Widget child, {
  required OrderCreateState state,
  ConfigValuesNotifier Function()? busConfig,
  ConfigValuesNotifier Function()? doorConfig,
}) {
  return ProviderScope(
    overrides: [
      shippingFeeBusProvider.overrideWith(
        busConfig ?? () => _DataConfigNotifier(['25000']),
      ),
      shippingFeeDoorProvider.overrideWith(
        doorConfig ?? () => _DataConfigNotifier(['20000']),
      ),
      orderCreateStateProvider.overrideWith(() => _FixedStateNotifier(state)),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('AC-1: uses OrderDeliverySection as canonical delivery widget',
      (tester) async {
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(onBack: () {}, onContinue: () {}),
      state: const OrderCreateState(wizardData: OrderWizardData()),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(OrderDeliverySection), findsOneWidget);
  });

  testWidgets('AC-4: Continue blocked when door delivery has empty address',
      (tester) async {
    var continued = false;
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(
        onBack: () {},
        onContinue: () => continued = true,
      ),
      state: const OrderCreateState(
        wizardData: OrderWizardData(deliveryType: 'door'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(OrdersLabels.continueLabel));
    await tester.pump();

    expect(continued, isFalse);
    expect(
      find.text(OrdersLabels.validationDeliveryAddressRequired),
      findsOneWidget,
    );
  });

  testWidgets('AC-4: Continue allowed when door delivery has an address',
      (tester) async {
    var continued = false;
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(
        onBack: () {},
        onContinue: () => continued = true,
      ),
      state: const OrderCreateState(
        wizardData: OrderWizardData(
          deliveryType: 'door',
          deliveryAddress: '12 Lê Lợi',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(OrdersLabels.continueLabel));
    await tester.pump();

    expect(continued, isTrue);
    expect(
      find.text(OrdersLabels.validationDeliveryAddressRequired),
      findsNothing,
    );
  });

  testWidgets('AC-4: Continue allowed for pickup without an address',
      (tester) async {
    var continued = false;
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(
        onBack: () {},
        onContinue: () => continued = true,
      ),
      state: const OrderCreateState(
        wizardData: OrderWizardData(deliveryType: 'pickup'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(OrdersLabels.continueLabel));
    await tester.pump();

    expect(continued, isTrue);
  });

  testWidgets('AC-6: shipping fee config loading shows a spinner',
      (tester) async {
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(onBack: () {}, onContinue: () {}),
      state: const OrderCreateState(
        wizardData: OrderWizardData(deliveryType: 'door'),
      ),
      doorConfig: _LoadingConfigNotifier.new,
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('AC-6: shipping fee config error shows error state with retry',
      (tester) async {
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(onBack: () {}, onContinue: () {}),
      state: const OrderCreateState(
        wizardData: OrderWizardData(deliveryType: 'door'),
      ),
      doorConfig: _ErrorConfigNotifier.new,
    ));
    await tester.pumpAndSettle();

    expect(find.text(VN.errorLoading), findsOneWidget);
    expect(find.text(VN.retry), findsOneWidget);
  });

  testWidgets('AC-3: tablet width centers content via responsive wrapper',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(onBack: () {}, onContinue: () {}),
      state: const OrderCreateState(wizardData: OrderWizardData()),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Stage1ResponsiveContent), findsOneWidget);
  });

  String deliveryPhoneText(WidgetTester tester) {
    final field = tester.widget<TextField>(
      find.ancestor(
        of: find.text(OrdersLabels.deliveryPhone),
        matching: find.byType(TextField),
      ),
    );
    return field.controller?.text ?? '';
  }

  testWidgets('UAT-2: selecting bus with empty delivery phone auto-fills from customerPhone',
      (tester) async {
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(onBack: () {}, onContinue: () {}),
      state: const OrderCreateState(
        wizardData: OrderWizardData(customerPhone: '0987654321'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(VN.deliveryBus));
    await tester.pumpAndSettle();

    expect(deliveryPhoneText(tester), '0987654321');
  });

  testWidgets('UAT-2: selecting door with empty delivery phone auto-fills from customerPhone',
      (tester) async {
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(onBack: () {}, onContinue: () {}),
      state: const OrderCreateState(
        wizardData: OrderWizardData(customerPhone: '0912000111'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(VN.deliveryDoor));
    await tester.pumpAndSettle();

    expect(deliveryPhoneText(tester), '0912000111');
  });

  testWidgets('UAT-2: does NOT overwrite a user-entered delivery phone',
      (tester) async {
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(onBack: () {}, onContinue: () {}),
      state: const OrderCreateState(
        wizardData: OrderWizardData(
          customerPhone: '0987654321',
          deliveryType: 'bus',
          deliveryPhone: '0900000000',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(deliveryPhoneText(tester), '0900000000');
  });

  testWidgets('UAT-2: does not auto-fill when customerPhone is empty',
      (tester) async {
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(onBack: () {}, onContinue: () {}),
      state: const OrderCreateState(
        wizardData: OrderWizardData(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(VN.deliveryBus));
    await tester.pumpAndSettle();

    expect(deliveryPhoneText(tester), '');
  });
}
