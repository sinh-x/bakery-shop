import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Valid paper mode values (must match server-side `usb_printer.PAPER_MODES`).
const paperModes = <String>['label', 'roll'];

/// Default paper mode when the server has no DB override and no env var set.
const paperModeDefault = 'label';

class PaperModeService {
  final Dio _dio;

  PaperModeService(this._dio);

  /// Returns the effective paper mode (`label` or `roll`) and the server
  /// default. The effective value reflects DB override precedence over env.
  Future<PaperModeStatus> getStatus() async {
    final response = await _dio.get('/api/orders/print/paper-mode');
    final data = response.data as Map<String, dynamic>;
    return PaperModeStatus(
      paperMode: data['paperMode'] as String,
      defaultMode: (data['default'] as String?) ?? paperModeDefault,
    );
  }

  /// Persists [mode] to `app_config.paper_mode`. Takes effect on the next
  /// print/status call (no server restart required).
  Future<void> setMode(String mode) async {
    await _dio.put(
      '/api/orders/print/paper-mode',
      data: {'paperMode': mode},
    );
  }
}

class PaperModeStatus {
  const PaperModeStatus({required this.paperMode, required this.defaultMode});

  final String paperMode;
  final String defaultMode;
}

final paperModeServiceProvider = Provider<PaperModeService>((ref) {
  final dio = ref.watch(dioProvider);
  return PaperModeService(dio);
});