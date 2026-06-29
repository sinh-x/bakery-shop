import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import '../../shared/utils/date_formatting.dart'
    show setServerTimezoneOffset, kDefaultServerTimezoneOffset;

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

/// Server-side configuration returned by `GET /api/config`.
class ServerConfig {
  final String timezone;
  final String timezoneOffset;

  const ServerConfig({required this.timezone, required this.timezoneOffset});

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        timezone: json['timezone'] as String,
        timezoneOffset: json['timezone_offset'] as String,
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

  Future<ServerConfig> getServerConfig() async {
    final response = await _dio.get('/api/config');
    return ServerConfig.fromJson(response.data as Map<String, dynamic>);
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

/// Fallback timezone offset used before the server config is fetched.
///
/// Defined in `date_formatting.dart` ([kDefaultServerTimezoneOffset]) to keep
/// a single source of truth — re-exported here for provider consumers.
const kDefaultTimezoneOffset = kDefaultServerTimezoneOffset;

/// Holds the server-configured timezone offset. Defaults to `+07:00` until
/// [initServerTimezone] updates it from the server config. Reading this
/// provider does NOT trigger a network fetch — call [initServerTimezone]
/// explicitly at real-app startup (see `main.dart`).
final serverTimezoneOffsetProvider = Provider<String>((ref) {
  return kDefaultTimezoneOffset;
});

/// Fetch the server timezone config and update [setServerTimezoneOffset].
///
/// Call once at app startup from `main.dart` (not from widget tests). Failures
/// are logged and the default offset is kept.
Future<void> initServerTimezone(ConfigService service) async {
  try {
    final config = await service.getServerConfig();
    setServerTimezoneOffset(config.timezoneOffset);
  } catch (error) {
    debugPrint('initServerTimezone: fetch failed, using default: $error');
  }
}
