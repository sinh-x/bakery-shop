import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/blank_service.dart';
import '../models/blank.dart';

/// Family AsyncNotifier for the stock audit log of a single blank (FR5/AC5).
///
/// Each instance manages the chronological list of [BlankStockLog] rows for
/// one blank, identified by [blankId]. Following the codebase convention for
/// `AsyncNotifierProvider.family` (arg as constructor param).
///
/// - `build()`: fetches the audit log via `BlankService.listStockLog(blankId)`.
/// - `refresh()`: reloads the log for this blank.
class BlankStockLogNotifier extends AsyncNotifier<List<BlankStockLog>> {
  final int blankId;

  BlankStockLogNotifier(this.blankId);

  @override
  Future<List<BlankStockLog>> build() =>
      ref.read(blankServiceProvider).listStockLog(blankId);

  /// Reloads the audit log for this blank from the server.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(blankServiceProvider).listStockLog(blankId),
    );
  }
}

/// Family provider: `ref.watch(blankStockLogProvider(blankId))`.
final blankStockLogProvider =
    AsyncNotifierProvider.family<BlankStockLogNotifier, List<BlankStockLog>,
        int>(
  BlankStockLogNotifier.new,
);