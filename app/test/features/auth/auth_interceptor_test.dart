import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/auth/auth_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen_test_helpers.dart';

void main() {
  group('AuthInterceptor', () {
    late SharedPreferences prefs;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
    });

    tearDown(() => container.dispose());

    AuthInterceptor buildInterceptor() => AuthInterceptor(
          readToken: () => container.read(authProvider).token,
          onUnauthorized: () => container.read(authProvider.notifier).handle401(),
        );

    test('attaches Authorization: Bearer <token> when authenticated', () async {
      final token = buildJwt({
        'sub': 'Sinh',
        'role': 'admin',
        'exp': 9999999999,
        'jti': 'jti-1',
      });
      await prefs.setString('auth_token', token);
      await prefs.setString('auth_username', 'Sinh');
      await prefs.setString('auth_role', 'admin');
      container.dispose();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );

      final capturedHeaders = <String, dynamic>{};
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..interceptors.add(buildInterceptor())
        ..interceptors.add(_CaptureInterceptor(onCapture: (opts) =>
            capturedHeaders.addAll(opts.headers)));

      await dio.get('/api/orders');
      expect(capturedHeaders['Authorization'], 'Bearer $token');
    });

    test('omits Authorization header when unauthenticated', () async {
      final capturedHeaders = <String, dynamic>{};
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
        ..interceptors.add(buildInterceptor())
        ..interceptors.add(_CaptureInterceptor(onCapture: (opts) =>
            capturedHeaders.addAll(opts.headers)));

      await dio.get('/api/orders');
      expect(capturedHeaders.containsKey('Authorization'), isFalse);
    });

    test('calls handle401 on a 401 response, clearing the token', () async {
      final token = buildJwt({
        'sub': 'Sinh',
        'role': 'admin',
        'exp': 9999999999,
        'jti': 'jti-1',
      });
      await prefs.setString('auth_token', token);
      await prefs.setString('auth_username', 'Sinh');
      await prefs.setString('auth_role', 'admin');
      container.dispose();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      expect(container.read(authProvider).isAuthenticated, isTrue);

      final interceptor = AuthInterceptor(
        readToken: () => container.read(authProvider).token,
        onUnauthorized: () => container.read(authProvider.notifier).handle401(),
      );
      // Simulate a server 401 via a custom HttpClientAdapter. Dio runs the
      // response through `validateStatus` — a 401 fails validation and is
      // converted to a DioException, which then flows through interceptor
      // `onError` callbacks in reverse order. This mirrors the real-world
      // 401-from-server path that AuthInterceptor is designed to handle.
      final dio = Dio(BaseOptions(
        baseUrl: 'http://localhost:8000',
        validateStatus: (_) => false,
      ))
        ..httpClientAdapter = _UnauthorizedAdapter()
        ..interceptors.add(interceptor);

      expect(
        dio.get('/api/orders'),
        throwsA(isA<DioException>()),
      );

      // Poll until the async handle401() flushes the token (up to ~500ms).
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (prefs.getString('auth_token') == null) break;
      }

      expect(prefs.getString('auth_token'), isNull);
      expect(container.read(authProvider).isAuthenticated, isFalse);
    });
  });
}

class _CaptureInterceptor extends Interceptor {
  _CaptureInterceptor({required this.onCapture});

  final void Function(RequestOptions options) onCapture;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    onCapture(options);
    handler.resolve(
      Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{},
      ),
    );
  }
}

/// HttpClientAdapter that returns a 401 response for every request, mirroring
/// the real-world server-401 path that triggers `AuthInterceptor.onError`.
class _UnauthorizedAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"detail":"unauthorized"}',
      401,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}