import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/auth/auth_provider.dart';
import 'package:bakery_app/features/auth/login_screen.dart';
import 'package:bakery_app/shared/labels/auth.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen_test_helpers.dart';

void main() {
  group('LoginScreen', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
    });

    testWidgets('renders username, password fields, and login button',
        (tester) async {
      await tester.pumpWidget(_buildApp(prefs: prefs));
      await tester.pump();
      expect(find.text(AuthLabels.usernameLabel), findsOneWidget);
      expect(find.text(AuthLabels.passwordLabel), findsOneWidget);
      expect(find.text(AuthLabels.loginButton), findsOneWidget);
    });

    testWidgets('shows invalid-credentials error on a 401 login failure',
        (tester) async {
      final dio = Dio()..interceptors.add(_LoginRejectInterceptor(401));
      await tester.pumpWidget(_buildApp(prefs: prefs, dio: dio));
      await tester.pump();

      await tester.enterText(
        find.byType(TextFormField).first,
        'wronguser',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'wrongpass',
      );
      await tester.tap(find.text(AuthLabels.loginButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(AuthLabels.invalidCredentials), findsOneWidget);
    });

    testWidgets('shows account-locked error on a 423 login failure',
        (tester) async {
      final dio = Dio()..interceptors.add(_LoginRejectInterceptor(423));
      await tester.pumpWidget(_buildApp(prefs: prefs, dio: dio));
      await tester.pump();

      await tester.enterText(find.byType(TextFormField).first, 'Sinh');
      await tester.enterText(find.byType(TextFormField).last, 'pw');
      await tester.tap(find.text(AuthLabels.loginButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(AuthLabels.accountLocked), findsOneWidget);
    });

    testWidgets('stores token and transitions to authenticated on success',
        (tester) async {
      final token = buildJwt({
        'sub': 'Sinh',
        'role': 'admin',
        'exp': 9999999999,
        'jti': 'jti-1',
      });
      final dio = Dio()..interceptors.add(_LoginOkInterceptor(token: token));
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextFormField).first, 'Sinh');
      await tester.enterText(find.byType(TextFormField).last, 'secret');
      await tester.tap(find.text(AuthLabels.loginButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final state = container.read(authProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.username, 'Sinh');
      expect(state.role, 'admin');
      expect(prefs.getString('auth_token'), isNotNull);
    });
  });
}

Widget _buildApp({required SharedPreferences prefs, Dio? dio}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (dio != null) dioProvider.overrideWithValue(dio),
    ],
    child: const MaterialApp(home: LoginScreen()),
  );
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
            'username': 'Sinh',
            'role': 'admin',
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