import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/expense_filter_card.dart';

/// State for the outstanding-debts list screen (DG-404 Phase 4.1 / FR2).
///
/// Owns the active debt-status filter and the loaded debts payload
/// (creditors list, total owed, count) plus the loading flag and
/// transient error string previously held as `setState` fields inside
/// `_DebtListScreenState`.
class DebtListState {
  const DebtListState({
    this.status = ExpenseDebtStatusFilter.all,
    this.loading = true,
    this.error,
    this.data = const <String, dynamic>{
      'creditors': <Map<String, dynamic>>[],
      'total_owed': 0.0,
      'count': 0,
    },
  });

  final ExpenseDebtStatusFilter status;
  final bool loading;
  final String? error;
  final Map<String, dynamic> data;

  DebtListState copyWith({
    ExpenseDebtStatusFilter? status,
    bool? loading,
    String? error,
    Map<String, dynamic>? data,
    bool clearError = false,
  }) {
    return DebtListState(
      status: status ?? this.status,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      data: data ?? this.data,
    );
  }
}

/// `Notifier` that owns the debt-list screen state (DG-404 Phase 4.1 /
/// FR2). The widget reads [debtListProvider] and invokes mutators; no
/// `setState` is required. The actual fetch is driven by the widget
/// reading the current status and calling its loader, then calling
/// [setData] / [setError] with the result.
class DebtListNotifier extends Notifier<DebtListState> {
  @override
  DebtListState build() => const DebtListState();

  void startReload() => state = state.copyWith(
        loading: true,
        clearError: true,
      );

  void setData(Map<String, dynamic> data) => state = state.copyWith(
        data: data,
        loading: false,
        clearError: true,
      );

  void setError(String message) => state = state.copyWith(
        error: message,
        loading: false,
      );

  void setStatus(ExpenseDebtStatusFilter value) =>
      state = state.copyWith(status: value);
}

/// Provider for the debt-list screen state.
final debtListProvider =
    NotifierProvider<DebtListNotifier, DebtListState>(DebtListNotifier.new);