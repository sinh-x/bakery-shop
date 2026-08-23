import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/event.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/labels/expenses.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/models/form_draft_context.dart';

class DebtSettlementDraft {
  const DebtSettlementDraft({
    this.amount = '',
    this.note = '',
    this.paymentMethod = OrdersLabels.methodCash,
    this.paymentSource = ExpensesLabels.paymentSourceDrawerCash,
  });

  final String amount;
  final String note;
  final String paymentMethod;
  final String paymentSource;

  DebtSettlementDraft copyWith({
    String? amount,
    String? note,
    String? paymentMethod,
    String? paymentSource,
  }) => DebtSettlementDraft(
    amount: amount ?? this.amount,
    note: note ?? this.note,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    paymentSource: paymentSource ?? this.paymentSource,
  );
}

/// State for the debt-settlement screen (DG-404 Phase 4.1 / FR2).
///
/// Owns the loaded [BakeryEvent] plus its derived totals (total debt,
/// settled-so-far), the loading and submitting flags, the load-error
/// string, and the form fields (`paymentMethod`, `paymentSource`)
/// previously held as `setState` fields inside
/// `_DebtSettlementScreenState`.
class DebtSettlementState {
  const DebtSettlementState({
    this.event,
    this.totalDebt = 0,
    this.settledSoFar = 0,
    this.loading = false,
    this.submitting = false,
    this.loadError,
    this.paymentMethod = OrdersLabels.methodCash,
    this.paymentSource = ExpensesLabels.paymentSourceDrawerCash,
  });

  final BakeryEvent? event;
  final int totalDebt;
  final int settledSoFar;
  final bool loading;
  final bool submitting;
  final String? loadError;
  final String paymentMethod;
  final String paymentSource;

  int get remaining {
    final r = totalDebt - settledSoFar;
    return r < 0 ? 0 : r;
  }

  DebtSettlementState copyWith({
    BakeryEvent? event,
    int? totalDebt,
    int? settledSoFar,
    bool? loading,
    bool? submitting,
    String? loadError,
    String? paymentMethod,
    String? paymentSource,
    bool clearLoadError = false,
  }) {
    return DebtSettlementState(
      event: event ?? this.event,
      totalDebt: totalDebt ?? this.totalDebt,
      settledSoFar: settledSoFar ?? this.settledSoFar,
      loading: loading ?? this.loading,
      submitting: submitting ?? this.submitting,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentSource: paymentSource ?? this.paymentSource,
    );
  }
}

/// `Notifier` that owns the debt-settlement screen state (DG-404 Phase
/// 4.1 / FR2). The widget reads [debtSettlementProvider] and invokes
/// mutators; no `setState` is required.
class DebtSettlementNotifier extends Notifier<DebtSettlementState> {
  DebtSettlementNotifier([this.context]);

  final FormDraftContext? context;
  DebtSettlementDraft _draft = const DebtSettlementDraft();
  DebtSettlementDraft get draft => _draft;
  DebtSettlementDraft get draftSnapshot => _draft;

  @override
  DebtSettlementState build() {
    ref.watch(formDraftSessionEpochProvider);
    _draft = const DebtSettlementDraft();
    if (context != null) {
      _draft =
          ref
              .read(formDraftSessionProvider.notifier)
              .readDraft<DebtSettlementDraft>(context!) ??
          const DebtSettlementDraft();
    }
    return DebtSettlementState(
      paymentMethod: _draft.paymentMethod,
      paymentSource: _draft.paymentSource,
    );
  }

  void startLoading() =>
      state = state.copyWith(loading: true, clearLoadError: true);

  void setLoadedEvent({
    required BakeryEvent event,
    required int totalDebt,
    required int settledSoFar,
  }) => state = state.copyWith(
    event: event,
    totalDebt: totalDebt,
    settledSoFar: settledSoFar,
    loading: false,
    clearLoadError: true,
  );

  void setLoadError(String message) =>
      state = state.copyWith(loadError: message, loading: false);

  void setSubmitting(bool value) => state = state.copyWith(submitting: value);

  void setPaymentMethod(String value) =>
      _updateDraft(_draft.copyWith(paymentMethod: value));

  void setPaymentSource(String value) =>
      _updateDraft(_draft.copyWith(paymentSource: value));

  void setAmount(String value) => _updateDraft(_draft.copyWith(amount: value));

  void setNote(String value) => _updateDraft(_draft.copyWith(note: value));

  void clearDraft() {
    _draft = const DebtSettlementDraft();
    state = state.copyWith(
      paymentMethod: _draft.paymentMethod,
      paymentSource: _draft.paymentSource,
    );
    if (context != null) {
      ref.read(formDraftSessionProvider.notifier).clearDraft(context!);
    }
  }

  bool clearAfterSuccess(DebtSettlementDraft expected) {
    if (context == null) {
      clearDraft();
      return true;
    }
    final cleared = ref
        .read(formDraftSessionProvider.notifier)
        .clearDraftIfUnchanged(context!, expected);
    if (cleared) {
      _draft = const DebtSettlementDraft();
      state = state.copyWith(
        paymentMethod: _draft.paymentMethod,
        paymentSource: _draft.paymentSource,
      );
    }
    return cleared;
  }

  void _updateDraft(DebtSettlementDraft next) {
    _draft = next;
    state = state.copyWith(
      paymentMethod: next.paymentMethod,
      paymentSource: next.paymentSource,
    );
    if (context != null) {
      ref.read(formDraftSessionProvider.notifier).retainDraft(context!, next);
    }
  }
}

/// Provider for the debt-settlement screen state.
final debtSettlementProvider =
    NotifierProvider<DebtSettlementNotifier, DebtSettlementState>(
      DebtSettlementNotifier.new,
    );

final contextualDebtSettlementProvider =
    NotifierProvider.family<
      DebtSettlementNotifier,
      DebtSettlementState,
      FormDraftContext
    >(DebtSettlementNotifier.new);
