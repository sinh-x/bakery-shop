import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import 'auth_service.dart';
import 'jwt_claims.dart';
import 'token_storage.dart';

/// Auth state surfaced to the UI and the router guard.
class AuthState {
  const AuthState({
    this.token,
    this.username,
    this.role,
    this.status = AuthStatus.unknown,
  });

  const AuthState.unauthenticated()
      : token = null,
        username = null,
        role = null,
        status = AuthStatus.unauthenticated;

  AuthState.authenticated({
    required this.token,
    required this.username,
    required this.role,
  }) : status = AuthStatus.authenticated;

  final String? token;
  final String? username;
  final String? role;
  final AuthStatus status;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isAdmin => role == 'admin';
}

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Riverpod notifier managing auth state.
///
/// Responsibilities:
/// - On `build()`: read the stored JWT from [TokenStorage]; if present and not
///   expired (per the `exp` claim, NFR2), transition to `authenticated`;
///   otherwise clear stale state and transition to `unauthenticated`.
/// - `login()`: call [AuthService], persist the token via [TokenStorage], and
///   transition to `authenticated` on success.
/// - `logout()`: clear stored token and transition to `unauthenticated`.
/// - `handle401()`: invoked by [AuthInterceptor] on a 401 response; clears the
///   token and transitions to `unauthenticated` so the router guard redirects
///   back to the login screen.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final storage = _storage();
    final token = storage.readToken();
    if (token == null) {
      return const AuthState.unauthenticated();
    }
    final claims = decodeJwt(token);
    if (claims == null) {
      debugPrint('auth_notifier: stored token could not be decoded; clearing');
      _clearSync(storage);
      return const AuthState.unauthenticated();
    }
    if (claims.isExpired) {
      debugPrint('auth_notifier: stored token expired; clearing');
      _clearSync(storage);
      return const AuthState.unauthenticated();
    }
    // Prefer the cached username/role from storage (set at login time). Fall
    // back to the JWT claims if the storage row is missing (e.g. an older
    // install upgraded in place).
    final username = storage.readUsername() ?? claims.subject;
    final role = storage.readRole() ?? claims.role;
    return AuthState.authenticated(
      token: token,
      username: username,
      role: role,
    );
  }

  TokenStorage _storage() => TokenStorage(ref.read(sharedPreferencesProvider));

  Future<void> login({required String username, required String password}) async {
    final service = ref.read(authServiceProvider);
    final result = await service.login(username: username, password: password);
    final storage = _storage();
    await storage.writeSession(
      token: result.token,
      username: result.username,
      role: result.role,
    );
    state = AuthState.authenticated(
      token: result.token,
      username: result.username,
      role: result.role,
    );
  }

  Future<void> logout() async {
    await _storage().clear();
    state = const AuthState.unauthenticated();
  }

  /// Called by [AuthInterceptor] when the server returns 401. Clears the
  /// stored token so the router guard routes back to the login screen.
  Future<void> handle401() async {
    await _storage().clear();
    state = const AuthState.unauthenticated();
  }

  void _clearSync(TokenStorage storage) {
    // ignore: discarded_futures — best-effort cleanup on read; the prefs API
    // is async but the in-memory cache updates synchronously.
    storage.clear();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);