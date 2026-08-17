import 'package:bakery_app/data/api/address_service.dart';
import 'package:bakery_app/data/models/address.dart';
import 'package:bakery_app/data/providers/missing_links_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [AddressService] with an in-memory missing-links store so the
/// provider resolves without a backend. Mirrors the
/// [address_library_provider_test] pattern (DG-385 Phase 5).
class _FakeAddressService extends AddressService {
  _FakeAddressService(this._store) : super(Dio());

  final List<MissingLinkItem> _store;
  int _refreshCalls = 0;

  @override
  Future<List<MissingLinkItem>> missingLinks({int? limit}) async {
    _refreshCalls++;
    return List<MissingLinkItem>.from(_store);
  }

  int get refreshCalls => _refreshCalls;
}

List<MissingLinkItem> _seedStore() => const <MissingLinkItem>[
      MissingLinkItem(deliveryAddress: '12 Nguyễn Huệ, Q1', orderCount: 5),
      MissingLinkItem(deliveryAddress: '45 Lê Lợi', orderCount: 2),
    ];

void main() {
  group('MissingLinksNotifier (DG-388 Phase 3 / FR1/AC1/AC5)', () {
    test('build fetches missing-links from the backend (FR1)', () async {
      final fake =
          _FakeAddressService(List<MissingLinkItem>.from(_seedStore()));
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final result = await container.read(missingLinksProvider.future);
      expect(result, hasLength(2));
      expect(result.first.deliveryAddress, '12 Nguyễn Huệ, Q1');
      expect(result.first.orderCount, 5);
      expect(result.last.deliveryAddress, '45 Lê Lợi');
      expect(result.last.orderCount, 2);
    });

    test('build surfaces backend errors as AsyncError (AC5)', () async {
      final fake = _ThrowingAddressService();
      // Disable Riverpod's default retry-on-Exception behavior so the
      // provider settles into AsyncError immediately after the first
      // failure (the screen's error state is what we're verifying).
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(fake)],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);

      // Watch the provider so it starts building; wait for the error to
      // surface in the state rather than awaiting `.future` (which races
      // with container disposal during teardown).
      container.read(missingLinksProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final state = container.read(missingLinksProvider);
      expect(state, isA<AsyncError<List<MissingLinkItem>>>());
    });

    test('refresh re-fetches from the backend (FR6/AC5 retry)', () async {
      final fake =
          _FakeAddressService(List<MissingLinkItem>.from(_seedStore()));
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container.read(missingLinksProvider.future);
      expect(fake.refreshCalls, 1);
      await container.read(missingLinksProvider.notifier).refresh();
      expect(fake.refreshCalls, 2);
      final list = container.read(missingLinksProvider).value!;
      expect(list, hasLength(2));
    });
  });
}

/// Service that always throws on `missingLinks()` to exercise the
/// error state.
class _ThrowingAddressService extends AddressService {
  _ThrowingAddressService() : super(Dio());

  @override
  Future<List<MissingLinkItem>> missingLinks({int? limit}) async {
    throw Exception('backend down');
  }
}