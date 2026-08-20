import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/address_service.dart';
import '../models/address.dart';

/// Missing-links list state for the Phase 3 missing-links screen
/// (DG-388 Phase 3 / FR1/FR2/FR6/AC1/AC2/AC5).
///
/// Mirrors the [AddressLibraryNotifier] pattern (DG-385 Phase 5): an
/// [AsyncNotifier] wrapping `GET /api/addresses/missing-links` with a
/// [refresh] helper used by the screen's pull-to-refresh (FR6) and the
/// error-state retry button (AC5). The backend returns up to 100 entries
/// ordered by ``orderCount`` descending (FR1), so the provider holds the
/// full list — no pagination state. The screen renders it lazily via
/// `ListView.builder` (NFR2).
///
/// Read-only by design: the missing-links screen is a viewing surface for
/// staff to spot gaps and open Google Maps externally; it does not edit
/// links in-place (out of scope per §5).
class MissingLinksNotifier extends AsyncNotifier<List<MissingLinkItem>> {
  @override
  Future<List<MissingLinkItem>> build() async {
    final service = ref.read(addressServiceProvider);
    return service.missingLinks();
  }

  /// Re-fetch the missing-links list from the backend (FR6 pull-to-refresh
  /// / AC5 retry). Surfaces errors via [AsyncError] so the screen can
  /// render the error state with a retry button.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(addressServiceProvider).missingLinks();
    });
  }
}

/// Missing-links provider (DG-388 Phase 3 / FR1/AC1/AC5).
/// `AsyncNotifierProvider` wrapping `GET /api/addresses/missing-links`,
/// mirroring `addressLibraryProvider`.
final missingLinksProvider =
    AsyncNotifierProvider<MissingLinksNotifier, List<MissingLinkItem>>(
  MissingLinksNotifier.new,
);