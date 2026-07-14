import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences keys for auth state.
const kAuthTokenKey = 'auth_token';
const kAuthUsernameKey = 'auth_username';
const kAuthRoleKey = 'auth_role';

/// Thin wrapper around [SharedPreferences] for reading/writing the JWT token
/// and the cached identity (username + role) decoded from the JWT claims.
///
/// Keeping this in a dedicated class (rather than reading prefs inline in the
/// provider) makes the storage boundary easy to mock in tests and keeps the
/// provider logic focused on state transitions.
class TokenStorage {
  TokenStorage(this._prefs);

  final SharedPreferences _prefs;

  /// Returns the stored JWT token or `null` if none is stored.
  String? readToken() => _prefs.getString(kAuthTokenKey);

  /// Returns the cached username (JWT `sub` claim) or `null`.
  String? readUsername() => _prefs.getString(kAuthUsernameKey);

  /// Returns the cached role (JWT `role` claim) or `null`.
  String? readRole() => _prefs.getString(kAuthRoleKey);

  /// Persists the token and the identity claims extracted from the JWT.
  Future<void> writeSession({
    required String token,
    required String username,
    required String role,
  }) async {
    await _prefs.setString(kAuthTokenKey, token);
    await _prefs.setString(kAuthUsernameKey, username);
    await _prefs.setString(kAuthRoleKey, role);
  }

  /// Clears all auth-related keys. Called on logout and on 401 responses.
  Future<void> clear() async {
    await _prefs.remove(kAuthTokenKey);
    await _prefs.remove(kAuthUsernameKey);
    await _prefs.remove(kAuthRoleKey);
  }
}