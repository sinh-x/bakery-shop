import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/settings_sections.dart';

/// State for the pre-login connection-test screen (DG-404 Phase 4.7).
///
/// Owns the `testing` flag and `testResult` previously held as
/// `setState` fields inside `_PreLoginSettingsScreenState`. The widget
/// reads [preLoginConnectionProvider] and invokes the notifier's
/// mutators; no `setState` is required.
class PreLoginConnectionState {
  const PreLoginConnectionState({
    this.testing = false,
    this.testResult,
  });

  final bool testing;
  final ConnectionResult? testResult;

  PreLoginConnectionState copyWith({
    bool? testing,
    ConnectionResult? testResult,
    bool clearTestResult = false,
  }) {
    return PreLoginConnectionState(
      testing: testing ?? this.testing,
      testResult:
          clearTestResult ? null : (testResult ?? this.testResult),
    );
  }
}

/// `Notifier` that owns the pre-login connection-test state
/// (DG-404 Phase 4.7). Sync state because all mutations are local; the
/// actual network test is driven by the widget reading this state and
/// reporting the result back.
class PreLoginConnectionNotifier extends Notifier<PreLoginConnectionState> {
  @override
  PreLoginConnectionState build() => const PreLoginConnectionState();

  void setTesting(bool value) =>
      state = state.copyWith(testing: value, clearTestResult: true);

  void setTestResult(ConnectionResult result) =>
      state = state.copyWith(testing: false, testResult: result);

  void clearTestResult() =>
      state = state.copyWith(clearTestResult: true);
}

/// Provider for the pre-login connection-test state. The widget reads
/// this and calls the notifier's mutators; no `setState` is required.
final preLoginConnectionProvider =
    NotifierProvider<PreLoginConnectionNotifier, PreLoginConnectionState>(
  PreLoginConnectionNotifier.new,
);