import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/address_service.dart';
import '../../data/models/address.dart';

/// Address-library CRUD state for the Phase 5 management screen
/// (DG-385 Phase 5 / FR6/FR8/AC6).
///
/// Mirrors the [TemplateListNotifier] pattern (DG-375 Phase 4): an
/// [AsyncNotifier] wrapping `GET /api/addresses/library` with create /
/// update / delete helpers that optimistically patch the cached list so
/// the UI updates without waiting for a full re-fetch. The search query
/// is held here (not in the widget) so the provider layer stays the
/// single source of truth and the screen rebuilds tightly around it.
///
/// Per the plan's NFR3 ("Follow existing patterns") we use the same
/// `AsyncNotifierProvider` shape as `templateListProvider` rather than
/// the legacy `StateNotifierProvider` mentioned in the plan checklist —
/// the codebase has migrated to Riverpod 3.x and has no `StateNotifier`
/// usages left, so this keeps the riverpod graph consistent with
/// `docs/flutter-coding-standards.md`.
class AddressLibraryNotifier extends AsyncNotifier<List<AddressLibraryEntry>> {
  String? _search;

  @override
  Future<List<AddressLibraryEntry>> build() async {
    final service = ref.read(addressServiceProvider);
    return service.listLibrary(search: _search);
  }

  /// Re-fetch the library from the backend, preserving the current
  /// [search] filter (FR6/AC6). Called after create/update/delete and
  /// from the screen's retry action on error.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(addressServiceProvider).listLibrary(search: _search);
    });
  }

  /// Update the search query and re-fetch (FR6/AC6 — "search by address
  /// text"). Empty [query] clears the filter and lists all entries.
  Future<void> search(String query) async {
    final trimmed = query.trim();
    _search = trimmed.isEmpty ? null : trimmed;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(addressServiceProvider).listLibrary(search: _search);
    });
  }

  /// Create a new address library entry (FR8/AC6). On success the new
  /// entry is appended to the cached list; the screen then calls
  /// [refresh] to pick up the backend's normalized ordering.
  Future<AddressLibraryEntry> createEntry({
    required String displayAddress,
    String? googleMapsUrl,
  }) async {
    final service = ref.read(addressServiceProvider);
    final created = await service.createLibraryEntry(
      displayAddress: displayAddress,
      googleMapsUrl: googleMapsUrl,
    );
    final existing = state.asData?.value ?? const <AddressLibraryEntry>[];
    state = AsyncData([...existing, created]);
    return created;
  }

  /// Update an entry (FR8/AC6). On success the matching cached entry is
  /// replaced with the updated value. The backend may return 409 on
  /// collision; that error surfaces via the returned future so the
  /// screen can show it.
  Future<AddressLibraryEntry> updateEntry(
    int id, {
    String? displayAddress,
    String? googleMapsUrl,
  }) async {
    final service = ref.read(addressServiceProvider);
    final updated = await service.updateLibraryEntry(
      id,
      displayAddress: displayAddress,
      googleMapsUrl: googleMapsUrl,
    );
    state = state.whenData(
      (entries) => entries.map((e) => e.id == id ? updated : e).toList(),
    );
    return updated;
  }

  /// Delete an entry (FR8/AC6). On success the entry is removed from the
  /// cached list.
  Future<void> deleteEntry(int id) async {
    final service = ref.read(addressServiceProvider);
    await service.deleteLibraryEntry(id);
    state = state.whenData(
      (entries) => entries.where((e) => e.id != id).toList(),
    );
  }
}

/// Address-library management provider (DG-385 Phase 5 / FR6/FR8/AC6).
/// `AsyncNotifierProvider` wrapping `GET /api/addresses/library` with
/// create / update / delete helpers, mirroring `templateListProvider`.
final addressLibraryProvider =
    AsyncNotifierProvider<AddressLibraryNotifier, List<AddressLibraryEntry>>(
  AddressLibraryNotifier.new,
);