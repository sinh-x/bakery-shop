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

  Future<void> createConfigValue(String configKey, String value, {int sortOrder = 0}) async {
    await _dio.post('/api/config/$configKey', data: {
      'value': value,
      'sort_order': sortOrder,
    });
  }

  Future<void> updateConfigValue(String configKey, String oldValue, String newValue, {int? sortOrder}) async {
    final data = <String, dynamic>{
      'old_value': oldValue,
      'new_value': newValue,
    };
    if (sortOrder != null) {
      data['sort_order'] = sortOrder;
    }
    await _dio.put('/api/config/$configKey', data: data);
  }

  Future<void> deleteConfigValue(String configKey, String value) async {
    await _dio.delete('/api/config/$configKey', queryParameters: {'value': value});
  }
}

final configServiceProvider = Provider<ConfigService>((ref) {
  final dio = ref.watch(dioProvider);
  return ConfigService(dio);
});
