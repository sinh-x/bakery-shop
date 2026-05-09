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

/// Shipping fee presets for bus delivery (fixed 25000).
final shippingFeeBusProvider = configValuesProvider('shipping_fee_bus');

/// Shipping fee presets for door delivery (tiered: 20000, 30000, 40000, 50000).
final shippingFeeDoorProvider = configValuesProvider('shipping_fee_door');

/// Extra items with prices (format: "name|price").
final orderExtrasProvider = configValuesProvider('order_extra');

/// Gift threshold in VND (single numeric value).
final giftThresholdProvider = configValuesProvider('gift_threshold');

/// Gift extras with prices (format: "name|price").
final giftExtrasProvider = configValuesProvider('gift_extra');
