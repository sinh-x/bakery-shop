import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bakery_app/shared/labels/shared.dart';
import '../widgets/settings_sections.dart';

/// State for the technical-settings tab of the settings screen
/// (DG-404 Phase 4.7).
///
/// Owns the connection-test (`testing`, `testResult`) and version-info
/// (`appVersion`, `serverVersion`) fields previously held as
/// `setState` fields inside `_SettingsScreenState`. The widget reads
/// [settingsScreenProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class SettingsScreenState {
  const SettingsScreenState({
    this.testing = false,
    this.testResult,
    this.appVersion = '',
    this.serverVersion = SharedLabels.serverVersionLoading,
  });

  final bool testing;
  final ConnectionResult? testResult;
  final String appVersion;
  final String serverVersion;

  SettingsScreenState copyWith({
    bool? testing,
    ConnectionResult? testResult,
    bool clearTestResult = false,
    String? appVersion,
    String? serverVersion,
  }) {
    return SettingsScreenState(
      testing: testing ?? this.testing,
      testResult:
          clearTestResult ? null : (testResult ?? this.testResult),
      appVersion: appVersion ?? this.appVersion,
      serverVersion: serverVersion ?? this.serverVersion,
    );
  }
}

/// `Notifier` that owns the settings-screen technical-tab state
/// (DG-404 Phase 4.7). Sync state because all mutations are local; the
/// actual network tests / package-info fetches are driven by the
/// widget reading this state and reporting results back.
class SettingsScreenNotifier extends Notifier<SettingsScreenState> {
  @override
  SettingsScreenState build() => const SettingsScreenState();

  void setAppVersion(String value) =>
      state = state.copyWith(appVersion: value);

  void setServerVersion(String value) =>
      state = state.copyWith(serverVersion: value);

  void setTesting(bool value) =>
      state = state.copyWith(testing: value, clearTestResult: true);

  void setTestResult(ConnectionResult result, {String? serverVersion}) =>
      state = state.copyWith(
        testing: false,
        testResult: result,
        serverVersion: serverVersion,
      );

  void clearTestResult() =>
      state = state.copyWith(clearTestResult: true);
}

/// Provider for the settings-screen technical-tab state. The widget
/// reads this and calls the notifier's mutators; no `setState` is
/// required.
final settingsScreenProvider =
    NotifierProvider<SettingsScreenNotifier, SettingsScreenState>(
  SettingsScreenNotifier.new,
);