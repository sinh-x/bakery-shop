import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/auth/password_change_screen.dart';
import 'package:bakery_app/shared/labels/auth.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen_test_helpers.dart';

void main() {
  group('PasswordChangeScreen (DG-319 Phase 5 / FR5 / AC3 / AC4)', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      // Seed an authenticated session so the change endpoint can be called.
      final token = buildJwt({
        'sub': 'Sinh',
        'role': 'admin',
        'exp': 9999999999,
        'jti': 'jti-pc',
      });
      await prefs.setString('auth_token', token);
      await prefs.setString('auth_username', 'Sinh');
      await prefs.setString('auth_role', 'admin');
    });

    testWidgets('renders old/new/confirm fields and change button',
        (tester) async {
      await tester.pumpWidget(_buildApp(prefs: prefs));
      await tester.pump();
      expect(find.text(AuthLabels.oldPasswordLabel), findsOneWidget);
      expect(find.text(AuthLabels.newPasswordLabel), findsOneWidget);
      expect(find.text(AuthLabels.confirmPasswordLabel), findsOneWidget);
      expect(find.text(AuthLabels.changePasswordButton), findsOneWidget);
    });

    testWidgets('AC4: empty fields show validation error before submission',
        (tester) async {
      await tester.pumpWidget(_buildApp(prefs: prefs));
      await tester.pump();

      await tester.tap(find.text(AuthLabels.changePasswordButton));
      await tester.pump();

      // Three required-field validators fire.
      expect(find.text(AuthLabels.passwordRequired), findsNWidgets(3));
    });

    testWidgets('AC3: new != confirm shows mismatch error before submission',
        (tester) async {
      await tester.pumpWidget(_buildApp(prefs: prefs));
      await tester.pump();

      await tester.enterText(find.byType(TextFormField).at(0), 'oldpass');
      await tester.enterText(find.byType(TextFormField).at(1), 'newpass');
      await tester.enterText(find.byType(TextFormField).at(2), 'different');

      await tester.tap(find.text(AuthLabels.changePasswordButton));
      await tester.pump();

      expect(find.text(AuthLabels.passwordsDoNotMatch), findsOneWidget);
    });

    testWidgets('shows old-password-incorrect error on a 401', (tester) async {
      final dio = Dio()..interceptors.add(_ChangePasswordRejectInterceptor(401));
      await tester.pumpWidget(_buildApp(prefs: prefs, dio: dio));
      await tester.pump();

      await tester.enterText(find.byType(TextFormField).at(0), 'wrongold');
      await tester.enterText(find.byType(TextFormField).at(1), 'newpass');
      await tester.enterText(find.byType(TextFormField).at(2), 'newpass');

      await tester.tap(find.text(AuthLabels.changePasswordButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(AuthLabels.oldPasswordIncorrect), findsOneWidget);
    });

    testWidgets('shows mismatch error on a 422', (tester) async {
      final dio = Dio()..interceptors.add(_ChangePasswordRejectInterceptor(422));
      await tester.pumpWidget(_buildApp(prefs: prefs, dio: dio));
      await tester.pump();

      await tester.enterText(find.byType(TextFormField).at(0), 'oldpass');
      await tester.enterText(find.byType(TextFormField).at(1), 'newpass');
      await tester.enterText(find.byType(TextFormField).at(2), 'newpass');

      await tester.tap(find.text(AuthLabels.changePasswordButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(AuthLabels.passwordsDoNotMatch), findsOneWidget);
    });
  });
}

Widget _buildApp({required SharedPreferences prefs, Dio? dio}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (dio != null) dioProvider.overrideWithValue(dio),
    ],
    child: const MaterialApp(home: PasswordChangeScreen()),
  );
}

class _ChangePasswordRejectInterceptor extends Interceptor {
  _ChangePasswordRejectInterceptor(this.code);

  final int code;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/auth/password' && options.method == 'PUT') {
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
      return;
    }
    handler.next(options);
  }
}
