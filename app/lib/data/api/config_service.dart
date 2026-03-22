import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class ConfigValue {
  final String value;
  final int sortOrder;
  final bool active;

  ConfigValue({
    required this.value,
    required this.sortOrder,
    required this.active,
  });

  factory ConfigValue.fromJson(Map<String, dynamic> json) => ConfigValue(
        value: json['value'] as String,
        sortOrder: (json['sort_order'] as num).toInt(),
        active: json['active'] == 1 || json['active'] == true,
      );
}

class ConfigService {
  final Dio _dio;

  ConfigService(this._dio);

  Future<List<ConfigValue>> getConfigValues(String configKey) async {
    final response = await _dio.get('/api/config/$configKey');
    final list = response.data as List;
    return list
        .map((json) => ConfigValue.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

final configServiceProvider = Provider<ConfigService>((ref) {
  final dio = ref.watch(dioProvider);
  return ConfigService(dio);
});
