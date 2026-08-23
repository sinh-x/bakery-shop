import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

const _unset = Object();

/// Local form state for the reconciliation sale/waste modal bottom
/// sheets (DG-404 Phase 4.7 / FR2).
///
/// Owns the `_paymentMethod`, `_paymentMethodError` (sale modal) and
/// `_wasteReasonError` (waste modal) fields previously mutated via
/// `setState` inside the modal content states. The quantity / unit
/// price / waste reason `TextEditingController`s stay on the widget
/// because `TextEditingController` lifecycle is an acceptable-use case
/// (see DG-404 guardrails). A `rebuildToken` counter is exposed so the
/// waste modal can force a rebuild when its waste-qty controller
/// listener fires (the controller text drives conditional UI). The
/// widget reads [reconciliationSellWasteModalProvider] and invokes the
/// notifier's mutators; no `setState` is required.
class ReconciliationSellWasteModalState {
  const ReconciliationSellWasteModalState({
    this.quantity = '',
    this.unitPrice = '',
    this.wasteReason = '',
    this.paymentMethod,
    this.paymentMethodError = false,
    this.wasteReasonError = false,
    this.rebuildToken = 0,
    this.initialized = false,
    this.initialQuantity = '',
    this.initialUnitPrice = '',
    this.initialWasteReason = '',
    this.initialPaymentMethod,
  });

  final String quantity;
  final String unitPrice;
  final String wasteReason;
  final String? paymentMethod;
  final bool paymentMethodError;
  final bool wasteReasonError;
  final int rebuildToken;
  final bool initialized;
  final String initialQuantity;
  final String initialUnitPrice;
  final String initialWasteReason;
  final String? initialPaymentMethod;

  ReconciliationSellWasteModalState copyWith({
    Object? paymentMethod = _unset,
    String? quantity,
    String? unitPrice,
    String? wasteReason,
    bool? paymentMethodError,
    bool? wasteReasonError,
    int? rebuildToken,
    bool? initialized,
    String? initialQuantity,
    String? initialUnitPrice,
    String? initialWasteReason,
    Object? initialPaymentMethod = _unset,
  }) {
    return ReconciliationSellWasteModalState(
      paymentMethod: identical(paymentMethod, _unset)
          ? this.paymentMethod
          : paymentMethod as String?,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      wasteReason: wasteReason ?? this.wasteReason,
      paymentMethodError: paymentMethodError ?? this.paymentMethodError,
      wasteReasonError: wasteReasonError ?? this.wasteReasonError,
      rebuildToken: rebuildToken ?? this.rebuildToken,
      initialized: initialized ?? this.initialized,
      initialQuantity: initialQuantity ?? this.initialQuantity,
      initialUnitPrice: initialUnitPrice ?? this.initialUnitPrice,
      initialWasteReason: initialWasteReason ?? this.initialWasteReason,
      initialPaymentMethod: identical(initialPaymentMethod, _unset)
          ? this.initialPaymentMethod
          : initialPaymentMethod as String?,
    );
  }
}

/// `Notifier` that owns the local form state for the reconciliation
/// sale/waste modal bottom sheets (DG-404 Phase 4.7 / FR2). Keyed by
/// the option key via a family provider so each modal instance
/// maintains its own form state.
/// Following the codebase convention for `NotifierProvider.family`
/// (arg as constructor param, see `ExpenseHistoryPhotoNotifier`).
class ReconciliationSellWasteModalNotifier
    extends Notifier<ReconciliationSellWasteModalState> {
  final FormDraftContext context;
  bool _clearingRegistry = false;

  ReconciliationSellWasteModalNotifier(this.context);

  @override
  ReconciliationSellWasteModalState build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) {
      state = const ReconciliationSellWasteModalState();
    });
    ref.listen(formDraftSessionProvider, (previous, next) {
      if (!_clearingRegistry &&
          previous?.containsKey(context) == true &&
          !next.containsKey(context)) {
        state = const ReconciliationSellWasteModalState();
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<ReconciliationSellWasteModalState>(context) ??
        const ReconciliationSellWasteModalState();
  }

  void initializeSale({
    required String quantity,
    required String unitPrice,
    required String? method,
  }) {
    if (state.initialized) return;
    state = state.copyWith(
      quantity: quantity,
      unitPrice: unitPrice,
      paymentMethod: method,
      initialized: true,
      initialQuantity: quantity,
      initialUnitPrice: unitPrice,
      initialPaymentMethod: method,
    );
  }

  void initializeWaste({required String quantity, required String reason}) {
    if (state.initialized) return;
    state = state.copyWith(
      quantity: quantity,
      wasteReason: reason,
      initialized: true,
      initialQuantity: quantity,
      initialWasteReason: reason,
    );
  }

  void setQuantity(String value) {
    state = state.copyWith(quantity: value);
    _retain();
  }

  void setUnitPrice(String value) {
    state = state.copyWith(unitPrice: value);
    _retain();
  }

  void setWasteReason(String value) {
    state = state.copyWith(wasteReason: value);
    _retain();
  }

  void setPaymentMethod(String? value) {
    state = state.copyWith(paymentMethod: value, paymentMethodError: false);
    _retain();
  }

  void setPaymentMethodError(bool value) =>
      state = state.copyWith(paymentMethodError: value);

  void setWasteReasonError(bool value) =>
      state = state.copyWith(wasteReasonError: value);

  void clearWasteReasonError() =>
      state = state.copyWith(wasteReasonError: false);

  void settleTransient() {
    state = state.copyWith(
      paymentMethodError: false,
      wasteReasonError: false,
      rebuildToken: 0,
    );
  }

  /// Bump the rebuild token so watchers rebuild (used by the waste
  /// modal's waste-qty controller listener to refresh conditional UI).
  void rebuild() =>
      state = state.copyWith(rebuildToken: state.rebuildToken + 1);

  void clear() {
    state = const ReconciliationSellWasteModalState();
    _clearRegistry();
  }

  void discardSale({
    required String quantity,
    required String unitPrice,
    required String? paymentMethod,
  }) {
    state = ReconciliationSellWasteModalState(
      quantity: quantity,
      unitPrice: unitPrice,
      paymentMethod: paymentMethod,
      initialized: true,
      initialQuantity: quantity,
      initialUnitPrice: unitPrice,
      initialPaymentMethod: paymentMethod,
    );
    _clearRegistry();
  }

  void discardWaste({required String quantity, required String reason}) {
    state = ReconciliationSellWasteModalState(
      quantity: quantity,
      wasteReason: reason,
      initialized: true,
      initialQuantity: quantity,
      initialWasteReason: reason,
    );
    _clearRegistry();
  }

  void _retain() {
    if (!state.isDirty) {
      _clearRegistry();
      return;
    }
    ref
        .read(formDraftSessionProvider.notifier)
        .retainDraft(
          context,
          state.copyWith(
            paymentMethodError: false,
            wasteReasonError: false,
            rebuildToken: 0,
          ),
        );
  }

  void _clearRegistry() {
    _clearingRegistry = true;
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    _clearingRegistry = false;
  }
}

extension on ReconciliationSellWasteModalState {
  bool get isDirty =>
      initialized &&
      (quantity != initialQuantity ||
          unitPrice != initialUnitPrice ||
          wasteReason != initialWasteReason ||
          paymentMethod != initialPaymentMethod);
}

FormDraftContext reconciliationActionDraftContext({
  required int productId,
  required String optionKey,
  required String action,
  String? variantId,
}) => FormDraftContext(
  formType: 'reconciliation-$action',
  mode: FormDraftMode.action,
  productId: '$productId',
  optionId: optionKey,
  variantId: variantId,
);

/// Family provider for the reconciliation sale/waste modal form state,
/// keyed by the option key.
final reconciliationSellWasteModalProvider =
    NotifierProvider.family<
      ReconciliationSellWasteModalNotifier,
      ReconciliationSellWasteModalState,
      FormDraftContext
    >(ReconciliationSellWasteModalNotifier.new);
