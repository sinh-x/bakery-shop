import 'package:bakery_app/data/api/address_service.dart';
import 'package:bakery_app/data/models/address.dart';
import 'package:bakery_app/features/orders/widgets/address_autocomplete_field.dart';
import 'package:bakery_app/providers/address/address_autocomplete_provider.dart';
import 'package:bakery_app/shared/labels/address_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAddressService extends AddressService {
  _FakeAddressService() : super(Dio());

  final List<AddressSuggestion> _suggestions = <AddressSuggestion>[
    const AddressSuggestion(
      id: 1,
      displayAddress: '123 Lê Lợi',
      googleMapsUrl: 'https://maps.app.goo.gl/abc',
      isCustomerAddress: true,
    ),
    const AddressSuggestion(
      id: 2,
      displayAddress: '45 Trần Phú',
      googleMapsUrl: null,
      isCustomerAddress: false,
    ),
  ];

  @override
  Future<List<AddressSuggestion>> autocomplete({
    required String query,
    int? customerId,
  }) async {
    return List<AddressSuggestion>.from(_suggestions);
  }
}

void main() {
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
            home: Scaffold(body: AddressAutocompleteField(controller: controller)),
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
            home: Scaffold(body: AddressAutocompleteField(controller: controller)),
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
            home: Scaffold(body: AddressAutocompleteField(controller: controller)),
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

  testWidgets(
    'AddressAutocompleteField hides overlay when field loses focus',
    (tester) async {
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
    },
  );
}