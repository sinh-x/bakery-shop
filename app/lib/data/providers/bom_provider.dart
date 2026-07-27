import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/blank_service.dart';
import '../models/blank.dart';

/// Family AsyncNotifier for BOM mappings of a single price_chip (FR2/AC2).
///
/// Each instance manages the list of [ProductBlankBom] rows assigned to one
/// price chip, identified by [priceChipId]. Following the codebase convention
/// for `AsyncNotifierProvider.family` (arg as constructor param).
///
/// - `build()`: fetches mappings via `BlankService.listBom(priceChipId)`.
/// - `refresh()`: reloads the mappings for this chip.
/// - `addBom(int blankId, double quantity)`: creates a mapping and refreshes.
/// - `updateBom(int bomId, double quantity)`: patches a mapping's quantity.
/// - `removeBom(int bomId)`: deletes a mapping and refreshes.
///
/// Each mutating method calls `BlankService` then refetches the list so the UI
/// always reflects the latest server state.
class BomNotifier extends AsyncNotifier<List<ProductBlankBom>> {
  final int priceChipId;

  BomNotifier(this.priceChipId);

  @override
  Future<List<ProductBlankBom>> build() =>
      ref.read(blankServiceProvider).listBom(priceChipId);

  /// Reloads the BOM mappings for this price chip from the server.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(blankServiceProvider).listBom(priceChipId),
    );
  }

  /// Creates a new BOM mapping for the active price chip and refreshes.
  Future<void> addBom(int blankId, double quantity) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(blankServiceProvider);
      await service.createBom(priceChipId, blankId, quantity);
      return service.listBom(priceChipId);
    });
  }

  /// Updates the quantity of an existing BOM mapping and refreshes.
  Future<void> updateBom(int bomId, double quantity) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(blankServiceProvider);
      await service.updateBom(priceChipId, bomId, quantity);
      return service.listBom(priceChipId);
    });
  }

  /// Deletes a BOM mapping and refreshes.
  Future<void> removeBom(int bomId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(blankServiceProvider);
      await service.deleteBom(priceChipId, bomId);
      return service.listBom(priceChipId);
    });
  }
}

/// Family provider: `ref.watch(bomProvider(chipId))`.
final bomProvider =
    AsyncNotifierProvider.family<BomNotifier, List<ProductBlankBom>, int>(
  BomNotifier.new,
);