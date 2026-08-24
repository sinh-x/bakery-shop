import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/api/address_service.dart';
import 'package:bakery_app/data/models/address.dart';
import 'package:bakery_app/features/orders/widgets/address_autocomplete_field.dart';
import 'package:bakery_app/features/orders/widgets/order_delivery_section.dart';
import 'package:bakery_app/features/orders/widgets/stage1_responsive_content.dart';
import 'package:bakery_app/features/orders/widgets/stage3_delivery_options_screen.dart';
import 'package:bakery_app/features/orders/widgets/order_wizard.dart';
import 'package:bakery_app/providers/address/address_autocomplete_provider.dart';
import 'package:bakery_app/data/providers/config_provider.dart';
import 'package:bakery_app/providers/order/order_create_state_provider.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:dio/dio.dart';
import 'package:bakery_app/shared/labels/shared.dart';

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

/// Fake [AddressService] used by the FB-1 auto-bind tests. Returns a
/// configurable grouped autocomplete response so each test can exercise
/// the bind / clear paths of `_onAddressSelected` via `updateGpsFields`.
class _FakeAddressService extends AddressService {
  _FakeAddressService(this._response) : super(Dio());

  final AddressAutocompleteResponse _response;

  @override
  Future<AddressAutocompleteResponse> autocomplete({
    required String query,
    int? customerId,
  }) async =>
      _response;
}

Widget _harness(
  Widget child, {
  required OrderCreateState state,
  ConfigValuesNotifier Function()? busConfig,
  ConfigValuesNotifier Function()? doorConfig,
  AddressService? addressService,
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
      if (addressService != null)
        addressServiceProvider.overrideWithValue(addressService),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// Reads the top-level [OrderCreateState] from the harness container so the
/// FB-1 tests can assert `updateGpsFields` routed the map link to the correct
/// field (read at submit), not the nested `wizardData.googleMapsUrl` that was
/// never read by the submission path (the c5 bug).
OrderCreateState readOrderCreateState(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Stage3DeliveryOptionsScreen)),
    listen: false,
  );
  return container.read(orderCreateStateProvider);
}

void main() {
  testWidgets('AC-1: uses OrderDeliverySection as canonical delivery widget',
      (tester) async {
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(
        onBack: () {},
        onContinue: () {},
        orderStateProvider: orderCreateStateProvider,
      ),
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
        orderStateProvider: orderCreateStateProvider,
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
        orderStateProvider: orderCreateStateProvider,
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
        orderStateProvider: orderCreateStateProvider,
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
      Stage3DeliveryOptionsScreen(
        onBack: () {},
        onContinue: () {},
        orderStateProvider: orderCreateStateProvider,
      ),
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
      Stage3DeliveryOptionsScreen(
        onBack: () {},
        onContinue: () {},
        orderStateProvider: orderCreateStateProvider,
      ),
      state: const OrderCreateState(
        wizardData: OrderWizardData(deliveryType: 'door'),
      ),
      doorConfig: _ErrorConfigNotifier.new,
    ));
    await tester.pumpAndSettle();

    expect(find.text(SharedLabels.errorLoading), findsOneWidget);
    expect(find.text(SharedLabels.retry), findsOneWidget);
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
      Stage3DeliveryOptionsScreen(
        onBack: () {},
        onContinue: () {},
        orderStateProvider: orderCreateStateProvider,
      ),
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
      Stage3DeliveryOptionsScreen(
        onBack: () {},
        onContinue: () {},
        orderStateProvider: orderCreateStateProvider,
      ),
      state: const OrderCreateState(
        wizardData: OrderWizardData(customerPhone: '0987654321'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(OrdersLabels.deliveryBus));
    await tester.pumpAndSettle();

    expect(deliveryPhoneText(tester), '0987654321');
  });

  testWidgets('UAT-2: selecting door with empty delivery phone auto-fills from customerPhone',
      (tester) async {
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(
        onBack: () {},
        onContinue: () {},
        orderStateProvider: orderCreateStateProvider,
      ),
      state: const OrderCreateState(
        wizardData: OrderWizardData(customerPhone: '0912000111'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(OrdersLabels.deliveryDoor));
    await tester.pumpAndSettle();

    expect(deliveryPhoneText(tester), '0912000111');
  });

  testWidgets('UAT-2: does NOT overwrite a user-entered delivery phone',
      (tester) async {
    await tester.pumpWidget(_harness(
      Stage3DeliveryOptionsScreen(
        onBack: () {},
        onContinue: () {},
        orderStateProvider: orderCreateStateProvider,
      ),
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
      Stage3DeliveryOptionsScreen(
        onBack: () {},
        onContinue: () {},
        orderStateProvider: orderCreateStateProvider,
      ),
      state: const OrderCreateState(
        wizardData: OrderWizardData(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(OrdersLabels.deliveryBus));
    await tester.pumpAndSettle();

    expect(deliveryPhoneText(tester), '');
  });

  // ── DG-388 Phase 5.6-c6 — FB-1 auto-bind routing tests ────────────────

  testWidgets(
    'FB-1: selecting a suggestion with a googleMapsUrl binds it to the top-level state',
    (tester) async {
      final fake = _FakeAddressService(const AddressAutocompleteResponse(
        pastOrders: <AddressSuggestion>[
          AddressSuggestion(
            id: 1,
            displayAddress: '123 Lê Lợi',
            googleMapsUrl: 'https://maps.app.goo.gl/abc',
          ),
        ],
        library: <AddressSuggestion>[],
      ));
      await tester.pumpWidget(_harness(
        Stage3DeliveryOptionsScreen(
          onBack: () {},
          onContinue: () {},
          orderStateProvider: orderCreateStateProvider,
        ),
        state: const OrderCreateState(
          wizardData: OrderWizardData(deliveryType: 'door'),
          latitude: 10.0,
          longitude: 106.0,
        ),
        addressService: fake,
      ));
      await tester.pumpAndSettle();

      // Drive the autocomplete: type a 2+ char query and wait for the debounce.
      await tester.enterText(
        find.descendant(
          of: find.byType(AddressAutocompleteField),
          matching: find.byType(TextFormField),
        ),
        '12',
      );
      await tester.pump(
        kAddressAutocompleteDebounce + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();

      // Tap the suggestion carrying a non-null googleMapsUrl.
      await tester.tap(find.text('123 Lê Lợi').first);
      await tester.pumpAndSettle();

      final state = readOrderCreateState(tester);
      expect(state.googleMapsUrl, 'https://maps.app.goo.gl/abc');
    },
  );

  testWidgets(
    'FB-1: selecting a suggestion with null googleMapsUrl clears the top-level link + stale lat/long',
    (tester) async {
      final fake = _FakeAddressService(const AddressAutocompleteResponse(
        pastOrders: <AddressSuggestion>[
          AddressSuggestion(
            id: 2,
            displayAddress: '45 Trần Phú',
            googleMapsUrl: null,
          ),
        ],
        library: <AddressSuggestion>[],
      ));
      await tester.pumpWidget(_harness(
        Stage3DeliveryOptionsScreen(
          onBack: () {},
          onContinue: () {},
          orderStateProvider: orderCreateStateProvider,
        ),
        // Start from a state that already has a bound link + coords, so the
        // clear path (selecting a suggestion with null googleMapsUrl) can be
        // observed to reset them.
        state: const OrderCreateState(
          wizardData: OrderWizardData(deliveryType: 'door'),
          latitude: 10.0,
          longitude: 106.0,
          googleMapsUrl: 'https://maps.app.goo.gl/stale',
        ),
        addressService: fake,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(AddressAutocompleteField),
          matching: find.byType(TextFormField),
        ),
        '45',
      );
      await tester.pump(
        kAddressAutocompleteDebounce + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('45 Trần Phú').first);
      await tester.pumpAndSettle();

      // Confirm the suggestion was actually selected (address text written in).
      expect(
        (tester.widget(
          find.descendant(
            of: find.byType(AddressAutocompleteField),
            matching: find.byType(TextFormField),
          ),
        ) as TextFormField)
            .controller!
            .text,
        '45 Trần Phú',
      );

      final state = readOrderCreateState(tester);
      // The address controller sync confirms the selection routed through the
      // shared controller, proving we read the live container.
      expect(state.wizardData.deliveryAddress, '45 Trần Phú');
      expect(state.googleMapsUrl, isNull);
      expect(state.latitude, isNull);
      expect(state.longitude, isNull);
    },
  );
}
