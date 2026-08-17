import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../features/auth/auth_provider.dart';

const kLoggedByKey = 'logged_by_name';

/// Provider for the staff member logging events (FR17).
///
/// When authenticated, returns the JWT `sub` claim (username) — read-only.
/// When unauthenticated (grace mode), returns a locally-persisted staff name
/// set via [LoggedByNotifier.setName]. The local value persists across app
/// restarts via SharedPreferences under the `logged_by_name` key.
///
/// This restores the pre-DG-029 behavior where unauthenticated staff could
/// self-identify for order/receipt attribution during the grace period.
final loggedByProvider = NotifierProvider<LoggedByNotifier, String>(
  LoggedByNotifier.new,
);

class LoggedByNotifier extends Notifier<String> {
  @override
  String build() {
    final auth = ref.watch(authProvider);
    if (auth.username != null) return auth.username!;
    final prefs = ref.read(sharedPreferencesProvider);
    return prefs.getString(kLoggedByKey) ?? '';
  }

  /// Persist a staff name for grace-mode attribution.
  ///
  /// When authenticated (JWT present), the value is read-only and this is a
  /// no-op — the authenticated identity always wins. When unauthenticated,
  /// saves to SharedPreferences and updates the provider state immediately.
  Future<void> setName(String name) async {
    final auth = ref.read(authProvider);
    if (auth.username != null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(kLoggedByKey, name);
    state = name;
  }
}