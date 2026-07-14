import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Builds a minimal JWT (header.payload.sig) with the given payload.
String buildJwt(Map<String, dynamic> payload) {
  final header = {'alg': 'HS256', 'typ': 'JWT'};
  String b64(Map<String, dynamic> m) {
    final json = jsonEncode(m);
    var s = base64Url.encode(utf8.encode(json));
    while (s.endsWith('=')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
  return '${b64(header)}.${b64(payload)}.sig';
}

/// A valid (non-expired) admin JWT for use in tests that need an
/// authenticated session without the full login flow. Built lazily (not
/// `const`) because [buildJwt] is not a const constructor.
final String kTestAdminToken = buildJwt({
  'sub': 'Sinh',
  'role': 'admin',
  'exp': 9999999999,
  'jti': 'test-jti',
});

/// SharedPreferences keys mirrored from `token_storage.dart` so test helpers
/// can seed auth state without depending on the production import.
const _kAuthTokenKey = 'auth_token';
const _kAuthUsernameKey = 'auth_username';
const _kAuthRoleKey = 'auth_role';

/// Seeds [SharedPreferences] with a valid auth session so the router guard
/// lets the app navigate past `/login` and `loggedByProvider` returns the
/// given [username]. Call this before constructing the [ProviderScope] in
/// tests that render [BakeryApp] or any screen behind the auth gate.
///
/// Returns the [SharedPreferences] instance so the caller can pass it to
/// `sharedPreferencesProvider.overrideWithValue`.
Future<SharedPreferences> seedAuthenticatedPrefs({
  String? token,
  String username = 'Sinh',
  String role = 'admin',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _kAuthTokenKey: token ?? kTestAdminToken,
    _kAuthUsernameKey: username,
    _kAuthRoleKey: role,
  });
  final prefs = await SharedPreferences.getInstance();
  return prefs;
}