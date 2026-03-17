import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kDefaultApiUrl = 'http://localhost:8000';
const kApiUrlKey = 'api_base_url';

/// Must be overridden in ProviderScope with SharedPreferences.getInstance().
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override sharedPreferencesProvider in ProviderScope');
});

class ApiBaseUrlNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final url = prefs.getString(kApiUrlKey) ?? kDefaultApiUrl;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  Future<void> setUrl(String url) async {
    final normalized = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(kApiUrlKey, normalized);
    state = normalized;
  }
}

final apiBaseUrlProvider =
    NotifierProvider<ApiBaseUrlNotifier, String>(ApiBaseUrlNotifier.new);

final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  return Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
  ));
});
