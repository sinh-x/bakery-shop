import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sync state for the management dashboard refresh-error flag
/// (DG-404 Phase 4.7 / FR2). Owns the `_refreshError` flag previously
/// held as a `setState` field inside
/// `ManagementDashboardBodyState` — set when the most recent
/// pull-to-refresh failed and cleared on the next successful refresh.
class ManagementDashboardRefreshState {
  const ManagementDashboardRefreshState({this.refreshError = false});

  final bool refreshError;

  ManagementDashboardRefreshState copyWith({bool? refreshError}) {
    return ManagementDashboardRefreshState(
      refreshError: refreshError ?? this.refreshError,
    );
  }
}

/// `Notifier` that owns the management-dashboard refresh-error flag
/// (DG-404 Phase 4.7 / FR2). Sync state because the mutation is local.
class ManagementDashboardBodyNotifier
    extends Notifier<ManagementDashboardRefreshState> {
  @override
  ManagementDashboardRefreshState build() =>
      const ManagementDashboardRefreshState();

  void setRefreshError(bool value) =>
      state = state.copyWith(refreshError: value);
}

/// Provider for the management-dashboard refresh-error flag.
final managementDashboardBodyProvider =
    NotifierProvider<ManagementDashboardBodyNotifier,
        ManagementDashboardRefreshState>(ManagementDashboardBodyNotifier.new);