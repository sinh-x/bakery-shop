import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, debugPrintStack, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/utils/date_formatting.dart' show ServerTimezone;
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

/// Server config returned by `GET /api/config` (DG-202 FR7).
class ServerConfig {
  final String timezone;
  final int timezoneOffset;

  ServerConfig({required this.timezone, required this.timezoneOffset});

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        timezone: json['timezone'] as String,
        timezoneOffset: (json['timezone_offset'] as num).toInt(),
      );
}

/// Fetches the server timezone from `GET /api/config` and configures the
/// shared [ServerTimezone] holder so all `formatDisplay*` helpers use the
/// server's timezone offset for display conversion (DG-202 AC6).
///
/// This runs before `runApp()` and therefore before the ProviderScope is
/// available, so it builds a one-off [Dio] from [SharedPreferences] rather
/// than depending on Riverpod. Failures are non-fatal: the [ServerTimezone]
/// defaults to the device's local offset, so display helpers keep working
/// when the API is unreachable.
///
/// Intentional raw Dio isolation (review-auto cycle 1 OPS-1): a standalone
/// [Dio] is used here — NOT the shared `dioProvider` — because:
/// 1. `GET /api/config` is an unauthenticated public endpoint, so it must
///    not carry the auth interceptors attached to `dioProvider`.
/// 2. This runs at startup before Riverpod's `ProviderScope` exists, so
///    `dioProvider` is not yet constructable.
/// Do not refactor this to use `dioProvider` without first verifying both
/// constraints no longer apply.
Future<void> initServerTimezone() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    const defaultUrl = kIsWeb ? '' : kDefaultApiUrl;
    final rawUrl = prefs.getString(kApiUrlKey) ?? defaultUrl;
    final baseUrl = rawUrl.endsWith('/') ? rawUrl.substring(0, rawUrl.length - 1) : rawUrl;
    // Raw Dio (not dioProvider): unauthenticated endpoint + pre-Riverpod startup.
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
    ));
    final response = await dio.get('/api/config');
    final config = ServerConfig.fromJson(response.data as Map<String, dynamic>);
    ServerTimezone.configure(config.timezone, config.timezoneOffset);
  } catch (error, stackTrace) {
    debugPrint('initServerTimezone: failed to fetch server config: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
