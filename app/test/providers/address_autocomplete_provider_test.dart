import 'package:bakery_app/data/api/address_service.dart';
import 'package:bakery_app/data/models/address.dart';
import 'package:bakery_app/providers/address/address_autocomplete_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAddressService extends AddressService {
  _FakeAddressService() : super(Dio());

  String? lastQuery;
  int? lastCustomerId;
  int callCount = 0;

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
    callCount += 1;
    lastQuery = query;
    lastCustomerId = customerId;
    return List<AddressSuggestion>.from(_suggestions);
  }
}

void main() {
  test(
    'addressAutocompleteProvider returns empty list when query too short',
    () async {
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(_FakeAddressService())],
      );
      addTearDown(container.dispose);

      const request = AddressAutocompleteRequest(query: 'a', customerId: null);
      final result =
          await container.read(addressAutocompleteProvider(request).future);
      expect(result, isEmpty);
    },
  );

  test(
    'addressAutocompleteProvider fetches suggestions for valid query and forwards customerId',
    () async {
      final fake = _FakeAddressService();
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      const request = AddressAutocompleteRequest(query: '123', customerId: 7);
      final result =
          await container.read(addressAutocompleteProvider(request).future);

      expect(result, hasLength(2));
      expect(fake.callCount, 1);
      expect(fake.lastQuery, '123');
      expect(fake.lastCustomerId, 7);
      expect(result.first.isCustomerAddress, isTrue);
      expect(result.first.googleMapsUrl, isNotNull);
    },
  );

  test(
    'AddressAutocompleteQueryNotifier debounces query changes',
    () async {
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(_FakeAddressService())],
      );
      addTearDown(container.dispose);

      final notifier =
          container.read(addressAutocompleteQueryProvider.notifier);

      // Rapid typing should not publish immediately.
      notifier.onQueryChanged('1', customerId: null);
      notifier.onQueryChanged('12', customerId: null);
      notifier.onQueryChanged('123', customerId: null);
      expect(container.read(addressAutocompleteQueryProvider).query, '');

      // After the debounce window the latest query is published.
      await Future.delayed(
        kAddressAutocompleteDebounce + const Duration(milliseconds: 50),
      );
      expect(container.read(addressAutocompleteQueryProvider).query, '123');
    },
  );

  test(
    'AddressAutocompleteQueryNotifier.onCustomerChanged updates immediately',
    () {
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(_FakeAddressService())],
      );
      addTearDown(container.dispose);

      final notifier =
          container.read(addressAutocompleteQueryProvider.notifier);
      notifier.onQueryChanged('123', customerId: null);
      notifier.onCustomerChanged(42);

      final request = container.read(addressAutocompleteQueryProvider);
      expect(request.customerId, 42);
      expect(request.query, '');
    },
  );

  test(
    'AddressAutocompleteQueryNotifier.clear cancels in-flight debounce',
    () async {
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(_FakeAddressService())],
      );
      addTearDown(container.dispose);

      final notifier =
          container.read(addressAutocompleteQueryProvider.notifier);
      notifier.onQueryChanged('123', customerId: null);
      notifier.clear();

      expect(container.read(addressAutocompleteQueryProvider).query, '');

      // Wait past the debounce to confirm clear cancelled the timer.
      await Future.delayed(
        kAddressAutocompleteDebounce + const Duration(milliseconds: 50),
      );
      expect(container.read(addressAutocompleteQueryProvider).query, '');
    },
  );

  test('AddressAutocompleteRequest equality keys on query + customerId', () {
    const a = AddressAutocompleteRequest(query: 'abc', customerId: 1);
    const b = AddressAutocompleteRequest(query: 'abc', customerId: 1);
    const c = AddressAutocompleteRequest(query: 'abc', customerId: 2);
    const d = AddressAutocompleteRequest(query: 'xyz', customerId: 1);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == c, isFalse);
    expect(a == d, isFalse);
  });

  test('AddressAutocompleteRequest.isValid requires 2+ non-space chars', () {
    expect(const AddressAutocompleteRequest(query: '', customerId: null).isValid,
        isFalse);
    expect(const AddressAutocompleteRequest(query: ' ', customerId: null).isValid,
        isFalse);
    expect(const AddressAutocompleteRequest(query: 'a', customerId: null).isValid,
        isFalse);
    expect(
        const AddressAutocompleteRequest(query: 'ab', customerId: null).isValid,
        isTrue);
    expect(
        const AddressAutocompleteRequest(query: '  abc  ', customerId: null)
            .isValid,
        isTrue);
  });
}