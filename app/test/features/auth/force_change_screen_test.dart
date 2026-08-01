import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/auth/force_change_screen.dart';
import 'package:bakery_app/shared/labels/auth.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen_test_helpers.dart';

void main() {
  group('ForceChangeScreen (DG-319 Phase 5 / FR9 / FR10 / AC7 / AC8)', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      final token = buildJwt({
        'sub': 'An',
        'role': 'staff',
        'exp': 9999999999,
        'jti': 'jti-fc',
      });
      await prefs.setString('auth_token', token);
      await prefs.setString('auth_username', 'An');
      await prefs.setString('auth_role', 'staff');
    });

    testWidgets('renders forced-change title and explanatory message',
        (tester) async {
      await tester.pumpWidget(_buildApp(prefs: prefs));
      await tester.pump();
      expect(find.text(AuthLabels.forcePasswordChangeTitle), findsWidgets);
      expect(find.text(AuthLabels.forcePasswordChangeMessage), findsOneWidget);
      expect(find.text(AuthLabels.changePasswordButton), findsOneWidget);
    });

    testWidgets('embeds the shared password change form (FR9 reuse)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(prefs: prefs));
      await tester.pump();
      // The form contributes the three password fields + the submit button.
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(find.text(AuthLabels.oldPasswordLabel), findsOneWidget);
      expect(find.text(AuthLabels.newPasswordLabel), findsOneWidget);
      expect(find.text(AuthLabels.confirmPasswordLabel), findsOneWidget);
    });
  });
}

Widget _buildApp({required SharedPreferences prefs, Dio? dio}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (dio != null) dioProvider.overrideWithValue(dio),
    ],
    child: const MaterialApp(home: ForceChangeScreen()),
  );
}
