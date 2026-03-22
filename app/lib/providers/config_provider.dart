import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/config_service.dart';

class ConfigValuesNotifier extends AsyncNotifier<List<String>> {
  final String configKey;

  ConfigValuesNotifier(this.configKey);

  @override
  Future<List<String>> build() async {
    final service = ref.read(configServiceProvider);
    final values = await service.getConfigValues(configKey);
    return values.map((v) => v.value).toList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(configServiceProvider);
      final values = await service.getConfigValues(configKey);
      return values.map((v) => v.value).toList();
    });
  }
}

final configValuesProvider =
    AsyncNotifierProvider.family<ConfigValuesNotifier, List<String>, String>(
  (configKey) => ConfigValuesNotifier(configKey),
);

/// Convenience provider for order source options.
final orderSourcesProvider = configValuesProvider('order_source');
