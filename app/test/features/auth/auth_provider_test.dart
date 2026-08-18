import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/shared/providers/auth_provider.dart';
import 'package:bakery_app/shared/providers/token_storage.dart';
import 'package:bakery_app/shared/providers/logged_by_provider.dart';
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

    test('login() surfaces forcePasswordChange flag when set (FR8)', () async {
      final token = buildJwt({
        'sub': 'An',
        'role': 'staff',
        'exp': 9999999999,
        'jti': 'jti-an',
      });
      final dio = Dio()
        ..interceptors.add(
          _LoginOkInterceptor(
            token: token,
            forcePasswordChange: true,
          ),
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
      expect(state.isAuthenticated, isTrue);
      expect(state.forcePasswordChange, isTrue);
    });

    test('changePassword() clears session on success (DG-319 Phase 4)',
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

      final dio = Dio()..interceptors.add(_ChangePasswordOkInterceptor());
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(authProvider).isAuthenticated, isTrue);

      await container.read(authProvider.notifier).changePassword(
            oldPassword: 'old',
            newPassword: 'new',
            confirmPassword: 'new',
          );

      expect(container.read(authProvider).isAuthenticated, isFalse);
      expect(prefs.getString('auth_token'), isNull);
    });

    test('changePassword() surfaces error on 401 (old password wrong)',
        () async {
      final token = buildJwt({
        'sub': 'Sinh',
        'role': 'admin',
        'exp': 9999999999,
        'jti': 'jti-1',
      });
      await TokenStorage(prefs)
          .writeSession(token: token, username: 'Sinh', role: 'admin');

      final dio = Dio()..interceptors.add(_LoginRejectInterceptor(401));
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(authProvider).isAuthenticated, isTrue);

      try {
        await container.read(authProvider.notifier).changePassword(
              oldPassword: 'wrong',
              newPassword: 'new',
              confirmPassword: 'new',
            );
        fail('Expected DioException');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 401);
      }
      // State unchanged on failure — user remains authenticated.
      expect(container.read(authProvider).isAuthenticated, isTrue);
    });

    test('clearForcePasswordChange() clears the flag (FR10)', () async {
      final token = buildJwt({
        'sub': 'Sinh',
        'role': 'admin',
        'exp': 9999999999,
        'jti': 'jti-1',
      });
      final dio = Dio()
        ..interceptors.add(
          _LoginOkInterceptor(
            token: token,
            forcePasswordChange: true,
          ),
        );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).login(
            username: 'Sinh',
            password: 'secret',
          );
      expect(container.read(authProvider).forcePasswordChange, isTrue);

      await container.read(authProvider.notifier).clearForcePasswordChange();

      expect(container.read(authProvider).forcePasswordChange, isFalse);
      expect(container.read(authProvider).isAuthenticated, isTrue);
    });

    test(
        'CQ-11: forcePasswordChange is persisted to storage and restored on '
        'restart (build())', () {
      // Simulate a previous login that wrote forcePasswordChange=true to
      // storage. On the next app start (build()), the flag must be restored
      // so the router guard redirects to /change-password.
      final token = buildJwt({
        'sub': 'An',
        'role': 'staff',
        'exp': 9999999999,
        'jti': 'jti-an',
      });
      prefs.setString('auth_token', token);
      prefs.setString('auth_username', 'An');
      prefs.setString('auth_role', 'staff');
      prefs.setBool('auth_force_password_change', true);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      final state = container.read(authProvider);
      expect(state.status, AuthStatus.authenticated);
      expect(state.forcePasswordChange, isTrue,
          reason: 'CQ-11: flag must be restored from storage on restart');
    });

    test(
        'CQ-11: clearForcePasswordChange() clears the flag from storage so a '
        'restart does not re-prompt', () async {
      final token = buildJwt({
        'sub': 'Sinh',
        'role': 'admin',
        'exp': 9999999999,
        'jti': 'jti-1',
      });
      final dio = Dio()
        ..interceptors.add(
          _LoginOkInterceptor(
            token: token,
            forcePasswordChange: true,
          ),
        );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authProvider.notifier).login(
            username: 'Sinh',
            password: 'secret',
          );
      expect(prefs.getBool('auth_force_password_change'), isTrue);

      await container.read(authProvider.notifier).clearForcePasswordChange();

      // The stored flag is removed (cleared) so a restart does not re-prompt.
      expect(prefs.getBool('auth_force_password_change'), isNull);
    });

    test('CQ-11: login() persists forcePasswordChange to storage', () async {
      final token = buildJwt({
        'sub': 'An',
        'role': 'staff',
        'exp': 9999999999,
        'jti': 'jti-an',
      });
      final dio = Dio()
        ..interceptors.add(
          _LoginOkInterceptor(
            token: token,
            forcePasswordChange: true,
          ),
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

      expect(prefs.getBool('auth_force_password_change'), isTrue);
    });
  });
}

class _LoginOkInterceptor extends Interceptor {
  _LoginOkInterceptor({required this.token, this.forcePasswordChange = false});

  final String token;
  final bool forcePasswordChange;

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
            if (forcePasswordChange) 'force_password_change': true,
          },
        ),
      );
      return;
    }
    handler.next(options);
  }
}

class _ChangePasswordOkInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/auth/password' && options.method == 'PUT') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: <String, dynamic>{'detail': 'Đổi mật khẩu thành công.'},
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
