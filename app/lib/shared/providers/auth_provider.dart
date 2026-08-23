import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../providers/form_draft_session_notifier.dart';
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
    this.forcePasswordChange = false,
  });

  const AuthState.unauthenticated()
    : token = null,
      username = null,
      role = null,
      status = AuthStatus.unauthenticated,
      forcePasswordChange = false;

  AuthState.authenticated({
    required this.token,
    required this.username,
    required this.role,
    this.forcePasswordChange = false,
  }) : status = AuthStatus.authenticated;

  final String? token;
  final String? username;
  final String? role;
  final AuthStatus status;

  /// FR8: when true, the router guard redirects to `/change-password` before
  /// the user can access the app shell.
  final bool forcePasswordChange;

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
    // CQ-11: restore the forced-password-change flag from storage so a user
    // whose force_password_change=1 cannot regain full app access by simply
    // restarting the app.
    final forcePasswordChange = storage.readForcePasswordChange();
    return AuthState.authenticated(
      token: token,
      username: username,
      role: role,
      forcePasswordChange: forcePasswordChange,
    );
  }

  TokenStorage _storage() => TokenStorage(ref.read(sharedPreferencesProvider));

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final service = ref.read(authServiceProvider);
    final result = await service.login(username: username, password: password);
    final storage = _storage();
    await storage.writeSession(
      token: result.token,
      username: result.username,
      role: result.role,
      forcePasswordChange: result.forcePasswordChange,
    );
    ref.read(formDraftSessionProvider.notifier).clearAll();
    state = AuthState.authenticated(
      token: result.token,
      username: result.username,
      role: result.role,
      forcePasswordChange: result.forcePasswordChange,
    );
  }

  /// Self-service password change (DG-319 Phase 4 / FR1).
  ///
  /// Calls [AuthService.changePassword] with the current and new passwords. On
  /// success the backend revokes all existing sessions (including this one),
  /// so the notifier clears local state and transitions to `unauthenticated`;
  /// the router guard then redirects to `/login` for a fresh login with the
  /// new password. Throws [DioException] on failure so the caller can surface
  /// the error.
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final service = ref.read(authServiceProvider);
    await service.changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
    // Backend revoked all sessions (including this one). Clear local state so
    // the router guard redirects to /login for a fresh login.
    await _endSession();
  }

  /// Clears a forced-password-change flag from local auth state after the user
  /// has completed a forced change (DG-319 Phase 4 / FR10). Called by the
  /// forced-change screen on a successful change that re-logs the user in.
  ///
  /// CQ-11: the flag is persisted in [TokenStorage] so it survives app
  /// restarts; clearing it here also clears the stored value so the user does
  /// not get re-prompted after the next restart.
  Future<void> clearForcePasswordChange() async {
    if (!state.forcePasswordChange) return;
    // Clear the persisted flag so the user is not re-prompted after restart.
    final storage = _storage();
    await storage.clearForcePasswordChange();
    state = AuthState.authenticated(
      token: state.token,
      username: state.username,
      role: state.role,
      forcePasswordChange: false,
    );
  }

  Future<void> logout() async {
    await _endSession();
  }

  /// Called by [AuthInterceptor] when the server returns 401. Clears the
  /// stored token so the router guard routes back to the login screen.
  Future<void> handle401() async {
    await _endSession();
  }

  Future<void> _endSession() async {
    await _storage().clear();
    ref.read(formDraftSessionProvider.notifier).clearAll();
    state = const AuthState.unauthenticated();
  }

  void _clearSync(TokenStorage storage) {
    // ignore: discarded_futures — best-effort cleanup on read; the prefs API
    // is async but the in-memory cache updates synchronously.
    storage.clear();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
