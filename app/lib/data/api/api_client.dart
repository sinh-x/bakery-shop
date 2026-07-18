import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint, debugPrintStack;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/auth_provider.dart';

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
    // On web, default to empty string (relative URL — same origin as the web server).
    // On mobile, default to the configured localhost URL.
    const defaultUrl = kIsWeb ? '' : kDefaultApiUrl;
    final url = prefs.getString(kApiUrlKey) ?? defaultUrl;
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

/// Cached device info headers, populated once on first Dio creation.
String _deviceModel = '';
String _appVersion = '';
String _osVersion = '';
bool _deviceInfoLoaded = false;

Future<void> _loadDeviceInfo() async {
  if (_deviceInfoLoaded) return;
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
  } catch (error, stackTrace) {
    debugPrint('api_client: failed to load app version: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  if (kIsWeb) {
    _deviceModel = 'Web Browser';
    _osVersion = 'Web';
  } else {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = await deviceInfo.androidInfo;
        _deviceModel = '${android.brand} ${android.model}';
        _osVersion = 'Android ${android.version.release}';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = await deviceInfo.iosInfo;
        _deviceModel = ios.utsname.machine;
        _osVersion = 'iOS ${ios.systemVersion}';
      }
    } catch (error, stackTrace) {
      debugPrint('api_client: failed to load device info: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
  _deviceInfoLoaded = true;
}

/// Dio interceptor that adds device info headers to every request.
class DeviceHeadersInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_appVersion.isNotEmpty) {
      options.headers['X-App-Version'] = _appVersion;
    }
    if (_deviceModel.isNotEmpty) {
      options.headers['X-Device-Model'] = _deviceModel;
    }
    if (_osVersion.isNotEmpty) {
      options.headers['X-OS-Version'] = _osVersion;
    }
    handler.next(options);
  }
}

/// Dio interceptor that attaches the JWT bearer token to every request and
/// routes 401 responses back to the login screen (FR15).
///
/// On each request it reads the current auth token via [readToken]. On a 401
/// response it invokes [onUnauthorized] which clears the stored token and
/// flips the auth state to `unauthenticated`; the router guard then
/// redirects to `/login`.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.readToken, required this.onUnauthorized});

  /// Returns the current JWT token, or `null`/empty if unauthenticated.
  final String? Function() readToken;

  /// Called once when a 401 response is received. Implementations should
  /// clear the stored token and transition the auth state.
  final Future<void> Function() onUnauthorized;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = readToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      // Fire-and-forget: clear the token so the router guard redirects to
      // /login on the next rebuild. Do not await here — onError must not block.
      onUnauthorized();
    }
    handler.next(err);
  }
}

final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
  ));
  dio.interceptors.add(DeviceHeadersInterceptor());
  dio.interceptors.add(AuthInterceptor(
    readToken: () => ref.read(authProvider).token,
    onUnauthorized: () => ref.read(authProvider.notifier).handle401(),
  ));
  // Load device info in background (headers will be empty until loaded)
  _loadDeviceInfo();
  return dio;
});
