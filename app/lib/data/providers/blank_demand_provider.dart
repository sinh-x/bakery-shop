import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/blank_service.dart';
import '../models/blank.dart';

/// AsyncNotifier for the demand planning screen (FR3/AC4).
///
/// - `build()`: fetches demand vs stock vs shortage per blank via
///   `BlankService.getDemand()`.
/// - `refresh()`: reloads the demand overview.
///
/// Demand is recalculated server-side from pending orders on each fetch, so
/// this notifier does not mutate state on the client — it only refetches.
class BlankDemandNotifier extends AsyncNotifier<List<BlankDemand>> {
  BlankService _service() => ref.read(blankServiceProvider);

  @override
  Future<List<BlankDemand>> build() async => _service().getDemand();

  /// Reloads the demand overview from the server.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async => _service().getDemand());
  }
}

final blankDemandProvider =
    AsyncNotifierProvider<BlankDemandNotifier, List<BlankDemand>>(
        BlankDemandNotifier.new);

/// Derived provider: demand vs stock vs shortage for a single blank by id
/// (DG-293 Phase 4 / FR5). Returns `null` when the blank has no demand row.
final blankDemandByIdProvider =
    FutureProvider.family<BlankDemand?, int>((ref, id) async {
  final list = await ref.watch(blankDemandProvider.future);
  return list.where((d) => d.blankId == id).firstOrNull;
});