import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/paper_mode_service.dart';

/// Notifier that manages the printer paper mode (label/roll).
///
/// Loads the effective paper mode from `GET /api/orders/print/paper-mode` and
/// persists selection via `PUT /api/orders/print/paper-mode` (DB-backed
/// override; env var is the fallback default). Selection takes effect on the
/// next print/status call — no server restart required (NFR2).
class PaperModeNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final service = ref.read(paperModeServiceProvider);
    final status = await service.getStatus();
    return status.paperMode;
  }

  /// Persists [mode] to the server and updates local state.
  Future<void> setMode(String mode) async {
    state = AsyncData(mode);
    try {
      final service = ref.read(paperModeServiceProvider);
      await service.setMode(mode);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

/// Provider for the effective printer paper mode.
final paperModeProvider =
    AsyncNotifierProvider<PaperModeNotifier, String>(PaperModeNotifier.new);

/// Provider for the configured trail length in mm (DG-184).
///
/// Defaults to 20 mm. Reads from the server paper-mode status endpoint
/// which returns the effective trail_mm (DB override > TRAIL_MM env var).
final trailMmProvider = FutureProvider<int>((ref) async {
  final service = ref.read(paperModeServiceProvider);
  final status = await service.getStatus();
  return status.trailMm;
});