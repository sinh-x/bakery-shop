import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

const _unset = Object();

/// Form state for the add-BOM-mapping bottom sheet (DG-404 Phase 4.4
/// / FR2).
///
/// Holds every field previously mutated via `setState` inside
/// `_BomAddSheetState`: `_selectedBlankId` and the `_saving` flag. The
/// quantity text controller stays on the widget because
/// `TextEditingController` lifecycle is an acceptable-use case (see
/// DG-404 guardrails). The widget reads [bomAddSheetProvider] and
/// invokes the notifier's mutators; no `setState` is required.
class BomAddSheetState {
  const BomAddSheetState({
    this.selectedBlankId,
    this.quantity = '1',
    this.saving = false,
  });

  final int? selectedBlankId;
  final String quantity;
  final bool saving;

  BomAddSheetState copyWith({
    Object? selectedBlankId = _unset,
    String? quantity,
    bool? saving,
  }) => BomAddSheetState(
    selectedBlankId: identical(selectedBlankId, _unset)
        ? this.selectedBlankId
        : selectedBlankId as int?,
    quantity: quantity ?? this.quantity,
    saving: saving ?? this.saving,
  );
}

/// `Notifier` that owns the add-BOM-sheet state (DG-404 Phase 4.4
/// / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_BomAddSheetState` are now exposed as notifier methods. The widget
/// reads the state via [bomAddSheetProvider] and rebuilds on change —
/// no `setState` is required.
class BomAddSheetNotifier extends Notifier<BomAddSheetState> {
  BomAddSheetNotifier(this.context);

  final FormDraftContext context;
  bool _clearingRegistry = false;

  @override
  BomAddSheetState build() {
    ref.listen(formDraftSessionEpochProvider, (_, _) {
      state = const BomAddSheetState();
    });
    ref.listen(formDraftSessionProvider, (previous, next) {
      if (!_clearingRegistry &&
          previous?.containsKey(context) == true &&
          !next.containsKey(context)) {
        state = const BomAddSheetState();
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<BomAddSheetState>(context) ??
        const BomAddSheetState();
  }

  void selectBlank(int? blankId) {
    state = state.copyWith(selectedBlankId: blankId);
    _retain();
  }

  void setQuantity(String value) {
    state = state.copyWith(quantity: value);
    _retain();
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
      state = const BomAddSheetState();
    } else {
      state = state.copyWith(saving: false);
    }
    return canClear;
  }

  void clear() {
    state = const BomAddSheetState();
    _clearRegistry();
  }

  void _retain() {
    if (state.selectedBlankId == null && state.quantity == '1') {
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

FormDraftContext bomAddDraftContext(int priceChipId) => FormDraftContext(
  formType: 'blank-bom-add',
  mode: FormDraftMode.action,
  optionId: '$priceChipId',
);

/// Provider for the add-BOM-sheet state. The sheet reads this and
/// calls the notifier's mutators; no `setState` is required.
final bomAddSheetProvider =
    NotifierProvider.family<
      BomAddSheetNotifier,
      BomAddSheetState,
      FormDraftContext
    >(BomAddSheetNotifier.new);
