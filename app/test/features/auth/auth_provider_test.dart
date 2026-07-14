import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/auth/auth_provider.dart';
import 'package:bakery_app/features/auth/token_storage.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen_test_helpers.dart';

void main() {
  group('AuthNotifier', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    test('build() returns unauthenticated when no token is stored', () {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      final state = container.read(authProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.token, isNull);
      expect(state.username, isNull);
    });

    test('build() returns authenticated when a valid token is stored', () {
      final token = buildJwt({
        'sub': 'Sinh',
        'role': 'admin',
        'exp': 9999999999,
        'jti': 'jti-1',
      });
      prefs.setString('auth_token', token);
      prefs.setString('auth_username', 'Sinh');
      prefs.setString('auth_role', 'admin');

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      final state = container.read(authProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.username, 'Sinh');
      expect(state.role, 'admin');
      expect(state.isAdmin, isTrue);
    });

    test('build() clears an expired token and returns unauthenticated', () {
      final expired = buildJwt({
        'sub': 'Sinh',
        'role': 'admin',
        'exp': 1,
        'jti': 'old',
      });
      prefs.setString('auth_token', expired);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      final state = container.read(authProvider);
      expect(state.status, AuthStatus.unauthenticated);
      expect(prefs.getString('auth_token'), isNull);
    });

    test('login() persists the token and transitions to authenticated', () async {
      final dio = Dio()
        ..interceptors.add(
          _LoginOkInterceptor(token: buildJwt({
            'sub': 'An',
            'role': 'staff',
            'exp': 9999999999,
            'jti': 'jti-an',
          })),
        );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).login(
            username: 'An',
            password: 'secret',
          );

      final state = container.read(authProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.username, 'An');
      expect(state.role, 'staff');
      expect(prefs.getString('auth_token'), isNotNull);
      expect(prefs.getString('auth_username'), 'An');
      expect(prefs.getString('auth_role'), 'staff');
    });

    test('logout() clears the token and transitions to unauthenticated',
        () async {
      // Seed authenticated state.
      final token = buildJwt({
        'sub': 'Sinh',
        'role': 'admin',
        'exp': 9999999999,
        'jti': 'jti-1',
      });
      await TokenStorage(prefs)
          .writeSession(token: token, username: 'Sinh', role: 'admin');

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(authProvider).isAuthenticated, isTrue);

      await container.read(authProvider.notifier).logout();
      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(prefs.getString('auth_token'), isNull);
    });

    test('loggedByProvider derives from auth username (FR17)', () {
      final token = buildJwt({
        'sub': 'Sinh',
        'role': 'admin',
        'exp': 9999999999,
        'jti': 'jti-1',
      });
      prefs.setString('auth_token', token);
      prefs.setString('auth_username', 'Sinh');
      prefs.setString('auth_role', 'admin');

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(loggedByProvider), 'Sinh');
    });

    test('loggedByProvider is empty when unauthenticated', () {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(loggedByProvider), '');
    });

    test('login() surfaces invalid-credentials error on 401', () async {
      final dio = Dio()..interceptors.add(_LoginRejectInterceptor(401));
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);
      try {
        await container.read(authProvider.notifier).login(
              username: 'x',
              password: 'y',
            );
        fail('Expected DioException');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 401);
      }
      expect(container.read(authProvider).isAuthenticated, isFalse);
    });
  });
}

class _LoginOkInterceptor extends Interceptor {
  _LoginOkInterceptor({required this.token});

  final String token;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/auth/login') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: <String, dynamic>{
            'token': token,
            'username': 'An',
            'role': 'staff',
          },
        ),
      );
      return;
    }
    handler.next(options);
  }
}

class _LoginRejectInterceptor extends Interceptor {
  _LoginRejectInterceptor(this.code);

  final int code;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(
      DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: code,
          data: <String, dynamic>{},
        ),
      ),
    );
  }
}