import 'dart:async';

import 'package:bakery_app/data/api/address_service.dart';
import 'package:bakery_app/data/models/address.dart';
import 'package:bakery_app/features/orders/widgets/address_autocomplete_field.dart';
import 'package:bakery_app/providers/address/address_autocomplete_provider.dart';
import 'package:bakery_app/shared/labels/address_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAddressService extends AddressService {
  _FakeAddressService() : super(Dio());

  /// Default grouped response. Tests may override this via [_responseOverride]
  /// to exercise single-group scenarios.
  static const _defaultResponse = AddressAutocompleteResponse(
    pastOrders: <AddressSuggestion>[
      AddressSuggestion(
        id: 1,
        displayAddress: '123 Lê Lợi',
        googleMapsUrl: 'https://maps.app.goo.gl/abc',
        isCustomerAddress: true,
      ),
    ],
    library: <AddressSuggestion>[
      AddressSuggestion(
        id: 2,
        displayAddress: '45 Trần Phú',
        googleMapsUrl: null,
        isCustomerAddress: false,
      ),
    ],
  );

  AddressAutocompleteResponse? _responseOverride;
  final queries = <String>[];
  final deferred = <String, Completer<AddressAutocompleteResponse>>{};

  set responseOverride(AddressAutocompleteResponse value) =>
      _responseOverride = value;

  @override
  Future<AddressAutocompleteResponse> autocomplete({
    required String query,
    int? customerId,
  }) async {
    queries.add(query);
    return deferred[query]?.future ??
        Future.value(_responseOverride ?? _defaultResponse);
  }
}

Future<void> _mountField(
  WidgetTester tester, {
  required TextEditingController controller,
  required _FakeAddressService service,
  required List<AddressSuggestion> selected,
  FocusNode? focusNode,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [addressServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: AddressAutocompleteField(
              controller: controller,
              focusNode: focusNode,
              customerId: 7,
              onSelected: selected.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _showSuggestions(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField), '12');
  await tester.pump(kAddressAutocompleteDebounce);
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    for (final suggestion in [
      _FakeAddressService._defaultResponse.pastOrders.single,
      _FakeAddressService._defaultResponse.library.single,
    ]) {
      testWidgets(
        '${kind.name} down/frame/up selects ${suggestion.displayAddress} exactly once',
        (tester) async {
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          final service = _FakeAddressService();
          final selected = <AddressSuggestion>[];
          await _mountField(
            tester,
            controller: controller,
            service: service,
            selected: selected,
          );
          await _showSuggestions(tester);
          // A pending edit must also be cancelled by choosing a visible tile.
          await tester.enterText(find.byType(TextFormField), '123');
          await tester.pump(const Duration(milliseconds: 100));

          final gesture = await tester.startGesture(
            tester.getCenter(find.text(suggestion.displayAddress)),
            kind: kind,
          );
          // A real pointer has a rendered frame between down and up.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          await gesture.up();
          await tester.pumpAndSettle();

          expect(controller.text, suggestion.displayAddress);
          expect(selected, [suggestion]);
          expect(find.byType(ListTile), findsNothing);
          await tester.pump(kAddressAutocompleteDebounce);
          await tester.pumpAndSettle();
          expect(service.queries, ['12']);
          expect(selected, [suggestion]);
          expect(find.byType(ListTile), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('outside mouse click dismisses without selecting', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    final selected = <AddressSuggestion>[];
    await _mountField(
      tester,
      controller: controller,
      service: _FakeAddressService(),
      selected: selected,
      focusNode: focusNode,
    );
    await _showSuggestions(tester);

    final gesture = await tester.startGesture(
      const Offset(700, 500),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isFalse);
    expect(find.byType(ListTile), findsNothing);
    expect(controller.text, '12');
    expect(selected, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late older response cannot undo selection or reopen dropdown', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final service = _FakeAddressService();
    final older = Completer<AddressAutocompleteResponse>();
    service.deferred['old'] = older;
    final selected = <AddressSuggestion>[];
    await _mountField(
      tester,
      controller: controller,
      service: service,
      selected: selected,
    );
    await tester.enterText(find.byType(TextFormField), 'old');
    await tester.pump(kAddressAutocompleteDebounce);
    await tester.pump();
    await _showSuggestions(tester);
    final suggestion = _FakeAddressService._defaultResponse.pastOrders.single;
    await tester.tap(find.text(suggestion.displayAddress));
    await tester.pumpAndSettle();
    older.complete(
      const AddressAutocompleteResponse(
        library: [AddressSuggestion(displayAddress: 'Stale address')],
      ),
    );
    await tester.pump(kAddressAutocompleteDebounce);
    await tester.pumpAndSettle();

    expect(controller.text, suggestion.displayAddress);
    expect(selected, [suggestion]);
    expect(selected.single.googleMapsUrl, suggestion.googleMapsUrl);
    expect(service.queries, ['old', '12']);
    expect(find.byType(ListTile), findsNothing);
    expect(tester.takeException(), isNull);
    // Explicit new user input is still allowed to query and show suggestions.
    await tester.enterText(find.byType(TextFormField), '45');
    await tester.pump(kAddressAutocompleteDebounce);
    await tester.pumpAndSettle();
    expect(service.queries, ['old', '12', '45']);
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(selected, [suggestion]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final pending in [false, true]) {
    testWidgets('disposal removes overlay with pending response=$pending', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final service = _FakeAddressService();
      final response = Completer<AddressAutocompleteResponse>();
      if (pending) service.deferred['12'] = response;
      final selected = <AddressSuggestion>[];
      await _mountField(
        tester,
        controller: controller,
        service: service,
        selected: selected,
      );
      await tester.enterText(find.byType(TextFormField), '12');
      await tester.pump(kAddressAutocompleteDebounce);
      await tester.pump();
      if (!pending) await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      if (pending) response.complete(_FakeAddressService._defaultResponse);
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      expect(find.text(AddressLabels.autocompleteLoading), findsNothing);
      expect(selected, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'AddressAutocompleteField renders default delivery address label',
    (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addressServiceProvider.overrideWithValue(_FakeAddressService()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AddressAutocompleteField(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      // The default VN delivery address label is rendered.
      expect(find.text('Địa chỉ giao hàng'), findsOneWidget);
      expect(find.text(AddressLabels.autocompleteHint), findsOneWidget);
    },
  );

  testWidgets(
    'AddressAutocompleteField does not fetch for queries shorter than 2 chars',
    (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addressServiceProvider.overrideWithValue(_FakeAddressService()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AddressAutocompleteField(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), 'a');
      await tester.pump();

      // Pump past debounce; no overlay should appear (query too short).
      await tester.pump(
        kAddressAutocompleteDebounce + const Duration(milliseconds: 50),
      );
      expect(find.byType(ListView), findsNothing);
    },
  );

  testWidgets(
    'AddressAutocompleteField shows suggestions overlay after debounce for 2+ chars',
    (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addressServiceProvider.overrideWithValue(_FakeAddressService()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AddressAutocompleteField(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), '12');
      await tester.pump();

      // Before the debounce completes, no suggestions yet.
      expect(find.text('123 Lê Lợi'), findsNothing);

      // After the debounce completes the suggestions appear.
      await tester.pump(
        kAddressAutocompleteDebounce + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();
      expect(find.text('123 Lê Lợi'), findsOneWidget);
      expect(find.text('45 Trần Phú'), findsOneWidget);
      expect(find.text(AddressLabels.customerAddressBadge), findsOneWidget);
    },
  );

  testWidgets(
    'AddressAutocompleteField writes selected address into controller and fires onSelected with map link',
    (tester) async {
      final controller = TextEditingController();
      AddressSuggestion? selected;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addressServiceProvider.overrideWithValue(_FakeAddressService()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AddressAutocompleteField(
                controller: controller,
                onSelected: (s) => selected = s,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), '12');
      await tester.pump(
        kAddressAutocompleteDebounce + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();

      // Tap the first suggestion.
      await tester.tap(find.text('123 Lê Lợi').first);
      await tester.pumpAndSettle();

      expect(controller.text, '123 Lê Lợi');
      expect(selected, isNotNull);
      expect(selected!.googleMapsUrl, 'https://maps.app.goo.gl/abc');
      expect(selected!.isCustomerAddress, isTrue);
    },
  );

  testWidgets('AddressAutocompleteField hides overlay when field loses focus', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          addressServiceProvider.overrideWithValue(_FakeAddressService()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AddressAutocompleteField(
              controller: controller,
              focusNode: focusNode,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), '12');
    await tester.pump(
      kAddressAutocompleteDebounce + const Duration(milliseconds: 50),
    );
    await tester.pumpAndSettle();
    expect(find.text('123 Lê Lợi'), findsOneWidget);

    focusNode.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('123 Lê Lợi'), findsNothing);
  });

  // ── DG-388 Phase 4 — Two-section dropdown (FR4 / AC3 / AC4) ─────────────

  testWidgets(
    'AddressAutocompleteField shows both section headers when both groups have results (FR4/AC3)',
    (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addressServiceProvider.overrideWithValue(_FakeAddressService()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AddressAutocompleteField(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), '12');
      await tester.pump(
        kAddressAutocompleteDebounce + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();

      // Both section headers render (FR4/AC3).
      expect(
        find.text(AddressLabels.autocompleteSectionPastOrders),
        findsOneWidget,
      );
      expect(
        find.text(AddressLabels.autocompleteSectionLibrary),
        findsOneWidget,
      );
      // Both groups' suggestions render.
      expect(find.text('123 Lê Lợi'), findsOneWidget);
      expect(find.text('45 Trần Phú'), findsOneWidget);
    },
  );

  testWidgets(
    'AddressAutocompleteField omits section headers when only library group has results (FR4)',
    (tester) async {
      final fake = _FakeAddressService();
      // Override response: only library group has results.
      fake.responseOverride = const AddressAutocompleteResponse(
        pastOrders: <AddressSuggestion>[],
        library: <AddressSuggestion>[
          AddressSuggestion(
            id: 2,
            displayAddress: '45 Trần Phú',
            googleMapsUrl: null,
            isCustomerAddress: false,
          ),
        ],
      );
      final controller = TextEditingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [addressServiceProvider.overrideWithValue(fake)],
          child: MaterialApp(
            home: Scaffold(
              body: AddressAutocompleteField(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), '45');
      await tester.pump(
        kAddressAutocompleteDebounce + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();

      // No section headers when only one group has results.
      expect(
        find.text(AddressLabels.autocompleteSectionPastOrders),
        findsNothing,
      );
      expect(find.text(AddressLabels.autocompleteSectionLibrary), findsNothing);
      // The single suggestion still renders inline.
      expect(find.text('45 Trần Phú'), findsOneWidget);
    },
  );

  testWidgets(
    'AddressAutocompleteField omits section headers when only pastOrders group has results (FR4)',
    (tester) async {
      final fake = _FakeAddressService();
      fake.responseOverride = const AddressAutocompleteResponse(
        pastOrders: <AddressSuggestion>[
          AddressSuggestion(
            id: 1,
            displayAddress: '123 Lê Lợi',
            googleMapsUrl: 'https://maps.app.goo.gl/abc',
            isCustomerAddress: true,
          ),
        ],
        library: <AddressSuggestion>[],
      );
      final controller = TextEditingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [addressServiceProvider.overrideWithValue(fake)],
          child: MaterialApp(
            home: Scaffold(
              body: AddressAutocompleteField(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), '12');
      await tester.pump(
        kAddressAutocompleteDebounce + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(AddressLabels.autocompleteSectionPastOrders),
        findsNothing,
      );
      expect(find.text(AddressLabels.autocompleteSectionLibrary), findsNothing);
      expect(find.text('123 Lê Lợi'), findsOneWidget);
    },
  );

  testWidgets(
    'Selecting a library-section suggestion writes address and fires onSelected (AC4)',
    (tester) async {
      final controller = TextEditingController();
      AddressSuggestion? selected;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addressServiceProvider.overrideWithValue(_FakeAddressService()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AddressAutocompleteField(
                controller: controller,
                onSelected: (s) => selected = s,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), '45');
      await tester.pump(
        kAddressAutocompleteDebounce + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();

      // Tap the library suggestion.
      await tester.tap(find.text('45 Trần Phú').first);
      await tester.pumpAndSettle();

      expect(controller.text, '45 Trần Phú');
      expect(selected, isNotNull);
      expect(selected!.displayAddress, '45 Trần Phú');
      expect(selected!.googleMapsUrl, isNull);
    },
  );
}
