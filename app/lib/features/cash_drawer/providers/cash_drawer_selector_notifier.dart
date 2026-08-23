import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

FormDraftContext cashDrawerActionContext(String drawerId, String action) =>
    FormDraftContext(
      formType: 'cash-drawer',
      mode: FormDraftMode.action,
      entityId: drawerId,
      optionId: action,
    );

/// Cash-drawer dialog selector state (DG-404 Phase 4.7 / FR2).
///
/// Owns the `_selectedValue` (source/destination) and `_selectedStaffName`
/// fields previously mutated via `setState` inside the `_CashDrawerSelector`
/// helper used by the cash-in / cash-out dialogs. A `rebuildCounter` replaces
/// the empty `setState(() {})` call that forced the staff-picker validation
/// error to render. The widget reads [cashDrawerSelectorProvider] and invokes
/// the notifier's mutators; no `setState` is required.
class CashDrawerSelectorState {
  const CashDrawerSelectorState({
    this.selectedValue = 'owner',
    this.selectedStaffName,
    this.amount = '',
    this.note = '',
    this.rebuildCounter = 0,
  });

  final String selectedValue;
  final String? selectedStaffName;
  final String amount;
  final String note;
  final int rebuildCounter;

  bool get isDirty =>
      selectedValue != 'owner' ||
      selectedStaffName != null ||
      amount.isNotEmpty ||
      note.isNotEmpty;

  CashDrawerSelectorState copyWith({
    String? selectedValue,
    String? selectedStaffName,
    String? amount,
    String? note,
    int? rebuildCounter,
    bool clearStaffName = false,
  }) => CashDrawerSelectorState(
    selectedValue: selectedValue ?? this.selectedValue,
    selectedStaffName: clearStaffName
        ? null
        : (selectedStaffName ?? this.selectedStaffName),
    amount: amount ?? this.amount,
    note: note ?? this.note,
    rebuildCounter: rebuildCounter ?? this.rebuildCounter,
  );
}

class CashDrawerSelectorNotifier extends Notifier<CashDrawerSelectorState> {
  CashDrawerSelectorNotifier(this.context);

  final FormDraftContext context;

  @override
  CashDrawerSelectorState build() {
    ref.watch(formDraftSessionEpochProvider);
    final drafts = ref.read(formDraftSessionProvider);
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(context) ?? false) &&
          !next.containsKey(context)) {
        state = const CashDrawerSelectorState();
      }
    });
    return drafts[context] as CashDrawerSelectorState? ??
        const CashDrawerSelectorState();
  }

  bool get hasRetainedDraft =>
      ref.read(formDraftSessionProvider).containsKey(context);

  void initialize(String value) {
    if (hasRetainedDraft) return;
    state = CashDrawerSelectorState(selectedValue: value);
  }

  void setSelectedValue(String value) =>
      _retain(state.copyWith(selectedValue: value, clearStaffName: true));

  void setSelectedStaffName(String? value) =>
      _retain(state.copyWith(selectedStaffName: value));

  void setAmount(String value) => _retain(state.copyWith(amount: value));

  void setNote(String value) => _retain(state.copyWith(note: value));

  void _retain(CashDrawerSelectorState next) {
    state = next;
    final registry = ref.read(formDraftSessionProvider.notifier);
    if (next.isDirty) {
      registry.retainDraft(
        context,
        CashDrawerSelectorState(
          selectedValue: next.selectedValue,
          selectedStaffName: next.selectedStaffName,
          amount: next.amount,
          note: next.note,
        ),
      );
    } else {
      registry.clearDraft(context);
    }
  }

  /// Bump the rebuild counter to force a re-render of the staff-picker
  /// validation error (replaces the pre-migration `setState(() {})`).
  void rebuild() =>
      state = state.copyWith(rebuildCounter: state.rebuildCounter + 1);

  void clear() {
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    state = const CashDrawerSelectorState();
  }
}

final cashDrawerSelectorProvider =
    NotifierProvider.family<
      CashDrawerSelectorNotifier,
      CashDrawerSelectorState,
      FormDraftContext
    >(CashDrawerSelectorNotifier.new);
