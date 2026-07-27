import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/blank_service.dart';
import '../models/blank.dart';

/// AsyncNotifier for the blanks CRUD screen (FR1/AC1).
///
/// - `build()`: fetches all blanks via `BlankService.listBlanks()`.
/// - `refresh()`: reloads the list.
/// - `createBlank(...)`: creates and refreshes.
/// - `updateBlank(int id, ...)`: updates and refreshes.
/// - `deleteBlank(int id)`: deletes and refreshes.
/// - `filterByCategory(String category)`: reloads filtered by category.
///
/// Each mutating method refreshes the cached list after the server confirms
/// the change so the UI always reflects the latest state.
class BlanksNotifier extends AsyncNotifier<List<Blank>> {
  BlankService _service() => ref.read(blankServiceProvider);

  @override
  Future<List<Blank>> build() async => _service().listBlanks();

  /// Reloads the full blank list from the server.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async => _service().listBlanks());
  }

  /// Creates a new blank and refreshes the list.
  Future<void> createBlank({
    required String name,
    String category = '',
    String unit = '',
    String notes = '',
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final created = await _service().createBlank(
        name: name,
        category: category,
        unit: unit,
        notes: notes,
      );
      ref.invalidate(blankByIdProvider(created.id));
      return _service().listBlanks();
    });
  }

  /// Updates an existing blank and refreshes the list.
  Future<void> updateBlank(
    int id, {
    String? name,
    String? category,
    String? unit,
    String? notes,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _service().updateBlank(
        id,
        name: name,
        category: category,
        unit: unit,
        notes: notes,
      );
      ref.invalidate(blankByIdProvider(id));
      return _service().listBlanks();
    });
  }

  /// Deletes a blank and refreshes the list.
  Future<void> deleteBlank(int id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _service().deleteBlank(id);
      ref.invalidate(blankByIdProvider(id));
      return _service().listBlanks();
    });
  }

  /// Reloads the list filtered by [category]. An empty [category] clears the
  /// filter and lists all blanks.
  Future<void> filterByCategory(String category) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () async => _service().listBlanks(
        category: category.isEmpty ? null : category,
      ),
    );
  }
}

final blanksProvider =
    AsyncNotifierProvider<BlanksNotifier, List<Blank>>(BlanksNotifier.new);

/// Family provider that fetches a single blank by id (used by the detail
/// screen). Falls back to filtering the cached list when available.
final blankByIdProvider =
    FutureProvider.family<Blank, int>((ref, id) async {
  final service = ref.read(blankServiceProvider);
  final all = await service.listBlanks();
  return all.firstWhere(
    (b) => b.id == id,
    orElse: () => throw StateError('Blank $id not found'),
  );
});

/// Reverse-lookup provider: products/work items linked to a blank
/// (DG-293 Phase 4 / FR3). Used by the blank detail screen's
/// "Sản phẩm liên kết" section.
final blankProductsProvider =
    FutureProvider.family<BlankProducts, int>((ref, id) async {
  final service = ref.read(blankServiceProvider);
  return service.getBlankProducts(id);
});