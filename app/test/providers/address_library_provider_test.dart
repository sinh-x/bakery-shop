import 'package:bakery_app/data/api/address_service.dart';
import 'package:bakery_app/data/models/address.dart';
import 'package:bakery_app/data/providers/address_library_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [AddressService] with an in-memory store so the library provider
/// resolves without a backend. Mirrors the template-providers test
/// pattern (DG-375 Phase 4).
class _FakeAddressService extends AddressService {
  _FakeAddressService(this._store) : super(Dio());

  final List<AddressLibraryEntry> _store;
  int _nextId = 100;

  String? _lastSearch;

  @override
  Future<List<AddressLibraryEntry>> listLibrary({String? search}) async {
    _lastSearch = search;
    if (search == null || search.isEmpty) {
      return List<AddressLibraryEntry>.from(_store);
    }
    final lower = search.toLowerCase();
    return _store
        .where((e) => e.displayAddress.toLowerCase().contains(lower))
        .toList();
  }

  @override
  Future<AddressLibraryEntry> createLibraryEntry({
    required String displayAddress,
    String? googleMapsUrl,
  }) async {
    final entry = AddressLibraryEntry(
      id: _nextId++,
      displayAddress: displayAddress,
      googleMapsUrl: googleMapsUrl,
    );
    _store.add(entry);
    return entry;
  }

  @override
  Future<AddressLibraryEntry> updateLibraryEntry(
    int id, {
    String? displayAddress,
    String? googleMapsUrl,
  }) async {
    final i = _store.indexWhere((e) => e.id == id);
    if (i < 0) {
      throw Exception('not found');
    }
    final existing = _store[i];
    final updated = AddressLibraryEntry(
      id: id,
      displayAddress: displayAddress ?? existing.displayAddress,
      googleMapsUrl: googleMapsUrl ?? existing.googleMapsUrl,
    );
    _store[i] = updated;
    return updated;
  }

  @override
  Future<void> deleteLibraryEntry(int id) async {
    _store.removeWhere((e) => e.id == id);
  }

  String? get lastSearch => _lastSearch;
}

List<AddressLibraryEntry> _seedStore() => const <AddressLibraryEntry>[
      AddressLibraryEntry(
        id: 1,
        displayAddress: '123 Lê Lợi',
        googleMapsUrl: 'https://maps.app.goo.gl/abc',
      ),
      AddressLibraryEntry(
        id: 2,
        displayAddress: '45 Trần Phú',
        googleMapsUrl: null,
      ),
    ];

void main() {
  group('AddressLibraryNotifier (DG-385 Phase 5 / FR6/FR8/AC6)', () {
    test('build fetches the library from the backend', () async {
      final fake = _FakeAddressService(List<AddressLibraryEntry>.from(_seedStore()));
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final result =
          await container.read(addressLibraryProvider.future);
      expect(result, hasLength(2));
      expect(result.first.displayAddress, '123 Lê Lợi');
      expect(fake.lastSearch, isNull);
    });

    test('search filters the list via the backend search param', () async {
      final fake = _FakeAddressService(List<AddressLibraryEntry>.from(_seedStore()));
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      // Force build first so the notifier exists.
      await container.read(addressLibraryProvider.future);
      await container.read(addressLibraryProvider.notifier).search('Lê Lợi');

      final result = container.read(addressLibraryProvider).value!;
      expect(result, hasLength(1));
      expect(result.first.displayAddress, '123 Lê Lợi');
      expect(fake.lastSearch, 'Lê Lợi');
    });

    test('search with empty string clears the filter', () async {
      final fake = _FakeAddressService(List<AddressLibraryEntry>.from(_seedStore()));
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container.read(addressLibraryProvider.future);
      await container.read(addressLibraryProvider.notifier).search('Lê');
      expect(container.read(addressLibraryProvider).value!, hasLength(1));
      await container.read(addressLibraryProvider.notifier).search('   ');
      expect(container.read(addressLibraryProvider).value!, hasLength(2));
      expect(fake.lastSearch, isNull);
    });

    test('createEntry appends to the cached list (FR8)', () async {
      final fake = _FakeAddressService(List<AddressLibraryEntry>.from(_seedStore()));
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container.read(addressLibraryProvider.future);
      final created =
          await container.read(addressLibraryProvider.notifier).createEntry(
        displayAddress: '78 Hai Bà Trưng',
        googleMapsUrl: 'https://maps.app.goo.gl/xyz',
      );
      expect(created.id, greaterThan(0));
      expect(container.read(addressLibraryProvider).value!, hasLength(3));
    });

    test('updateEntry replaces the cached entry (FR8)', () async {
      final fake = _FakeAddressService(List<AddressLibraryEntry>.from(_seedStore()));
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container.read(addressLibraryProvider.future);
      final updated =
          await container.read(addressLibraryProvider.notifier).updateEntry(
        1,
        displayAddress: '123 Lê Lợi (đã sửa)',
      );
      expect(updated.displayAddress, '123 Lê Lợi (đã sửa)');
      final list = container.read(addressLibraryProvider).value!;
      expect(list.firstWhere((e) => e.id == 1).displayAddress,
          '123 Lê Lợi (đã sửa)');
    });

    test('deleteEntry removes the cached entry (FR8)', () async {
      final fake = _FakeAddressService(List<AddressLibraryEntry>.from(_seedStore()));
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container.read(addressLibraryProvider.future);
      await container.read(addressLibraryProvider.notifier).deleteEntry(1);
      final list = container.read(addressLibraryProvider).value!;
      expect(list, hasLength(1));
      expect(list.where((e) => e.id == 1), isEmpty);
    });

    test('refresh re-fetches from the backend', () async {
      final fake = _FakeAddressService(List<AddressLibraryEntry>.from(_seedStore()));
      final container = ProviderContainer(
        overrides: [addressServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container.read(addressLibraryProvider.future);
      // Mutate the underlying store directly, then refresh.
      fake.createLibraryEntry(displayAddress: 'sneaky');
      await container.read(addressLibraryProvider.notifier).refresh();
      expect(container.read(addressLibraryProvider).value!, hasLength(3));
    });
  });
}