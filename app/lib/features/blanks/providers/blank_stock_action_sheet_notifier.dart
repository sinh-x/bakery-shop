import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

/// Form state for the blank stock-action bottom sheet (DG-404 Phase
/// 4.4 / FR2).
///
/// Holds the `_saving` flag previously mutated via `setState` inside
/// `_BlankStockActionSheetState`. The quantity / produced-date /
/// expiry-date text controllers stay on the widget because
/// `TextEditingController` lifecycle is an acceptable-use case (see
/// DG-404 guardrails). The widget reads [blankStockActionSheetProvider]
/// and invokes the notifier's mutators; no `setState` is required.
class BlankStockActionSheetState {
  const BlankStockActionSheetState({
    this.quantity = '1',
    this.producedDate = '',
    this.expiryDate = '',
    this.saving = false,
  });

  final String quantity;
  final String producedDate;
  final String expiryDate;
  final bool saving;

  BlankStockActionSheetState copyWith({
    String? quantity,
    String? producedDate,
    String? expiryDate,
    bool? saving,
  }) => BlankStockActionSheetState(
    quantity: quantity ?? this.quantity,
    producedDate: producedDate ?? this.producedDate,
    expiryDate: expiryDate ?? this.expiryDate,
    saving: saving ?? this.saving,
  );
}

/// `Notifier` that owns the blank stock-action-sheet state (DG-404
/// Phase 4.4 / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_BlankStockActionSheetState` are now exposed as notifier methods.
/// The widget reads the state via
/// [blankStockActionSheetProvider] and rebuilds on change — no
/// `setState` is required.
class BlankStockActionSheetNotifier
    extends Notifier<BlankStockActionSheetState> {
  BlankStockActionSheetNotifier(this.context);

  final FormDraftContext context;
  bool _clearingRegistry = false;

  @override
  BlankStockActionSheetState build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) {
      state = const BlankStockActionSheetState();
    });
    ref.listen(formDraftSessionProvider, (previous, next) {
      if (!_clearingRegistry &&
          previous?.containsKey(context) == true &&
          !next.containsKey(context)) {
        state = const BlankStockActionSheetState();
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<BlankStockActionSheetState>(context) ??
        const BlankStockActionSheetState();
  }

  void setSaving(bool value) => state = state.copyWith(saving: value);

  Object? get retainedDraft => ref.read(formDraftSessionProvider)[context];

  bool completeSuccess(Object? submittedDraft) {
    final drafts = ref.read(formDraftSessionProvider.notifier);
    final currentDraft = ref.read(formDraftSessionProvider)[context];
    final canClear = submittedDraft == null
        ? currentDraft == null
        : drafts.clearDraftIfUnchanged(context, submittedDraft);
    if (canClear) {
      state = const BlankStockActionSheetState();
    } else {
      state = state.copyWith(saving: false);
    }
    return canClear;
  }

  void setQuantity(String value) {
    state = state.copyWith(quantity: value);
    _retain();
  }

  void setProducedDate(String value) {
    state = state.copyWith(producedDate: value);
    _retain();
  }

  void setExpiryDate(String value) {
    state = state.copyWith(expiryDate: value);
    _retain();
  }

  void clear() {
    state = const BlankStockActionSheetState();
    _clearRegistry();
  }

  void _retain() {
    if (!state.isDirty) {
      _clearRegistry();
      return;
    }
    ref
        .read(formDraftSessionProvider.notifier)
        .retainDraft(context, state.copyWith(saving: false));
  }

  void _clearRegistry() {
    _clearingRegistry = true;
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    _clearingRegistry = false;
  }
}

extension on BlankStockActionSheetState {
  bool get isDirty =>
      quantity != '1' || producedDate.isNotEmpty || expiryDate.isNotEmpty;
}

FormDraftContext blankStockActionDraftContext({
  required int blankId,
  required String action,
}) => FormDraftContext(
  formType: 'blank-stock-action:$action',
  mode: FormDraftMode.action,
  entityId: '$blankId',
);

/// Provider for the blank stock-action-sheet state. The sheet reads
/// this and calls the notifier's mutators; no `setState` is required.
final blankStockActionSheetProvider =
    NotifierProvider.family<
      BlankStockActionSheetNotifier,
      BlankStockActionSheetState,
      FormDraftContext
    >(BlankStockActionSheetNotifier.new);
