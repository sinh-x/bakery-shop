import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/blank_service.dart';
import '../models/blank.dart';

/// AsyncNotifier for the blank stock tracking screen (FR4/AC3).
///
/// - `build()`: fetches current net stock per blank via `BlankService.getStock()`.
/// - `refresh()`: reloads the stock overview.
/// - `recordProduction(int blankId, double quantity, ...)`: records a
///   production entry (adds stock) and refreshes.
/// - `recordUsage(int blankId, double quantity, ...)`: records a usage entry
///   (subtracts stock) and refreshes.
///
/// Both mutating methods call `BlankService.recordStock()` with the
/// appropriate `type` and then reload the stock summary so the UI reflects
/// the updated net quantities.
class BlankStockNotifier extends AsyncNotifier<List<BlankStockSummary>> {
  BlankService _service() => ref.read(blankServiceProvider);

  @override
  Future<List<BlankStockSummary>> build() async => _service().getStock();

  /// Reloads the stock overview from the server.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async => _service().getStock());
  }

  /// Records a production entry (nhập kho) and refreshes the stock overview.
  Future<void> recordProduction(
    int blankId,
    double quantity, {
    String producedDate = '',
    String? expiryDate,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _service().recordStock(
        blankId,
        quantity,
        'production',
        producedDate: producedDate,
        expiryDate: expiryDate,
      );
      return _service().getStock();
    });
  }

  /// Records a usage entry (xuất kho) and refreshes the stock overview.
  Future<void> recordUsage(
    int blankId,
    double quantity, {
    String producedDate = '',
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _service().recordStock(
        blankId,
        quantity,
        'usage',
        producedDate: producedDate,
      );
      return _service().getStock();
    });
  }
}

final blankStockProvider =
    AsyncNotifierProvider<BlankStockNotifier, List<BlankStockSummary>>(
        BlankStockNotifier.new);