import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

/// Work-item edit card state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_expanded`, `_isBirthday`, `_rutTien`, `_candleType`,
/// `_editingCashAmount`, `_savedCashAmount`, `_savedCashFee`, and
/// `_floorWarning` fields previously mutated via `setState` inside
/// `_WorkItemEditCardState`. The TextEditingController-backed
/// notes/age/price/cash-amount/cash-fee fields stay on the widget
/// (TextEditingController lifecycle is acceptable-use per DG-404
/// guardrails). The widget reads [workItemEditCardProvider] (family keyed
/// by work-item id) and invokes the notifier's mutators; no `setState`
/// is required.
class WorkItemEditCardState {
  const WorkItemEditCardState({
    this.expanded = true,
    this.isBirthday = false,
    this.rutTien = false,
    this.candleType,
    this.editingCashAmount = false,
    this.savedCashAmount = '',
    this.savedCashFee = '',
    this.floorWarning,
    this.notes = '',
    this.age = '',
    this.price = '',
    this.cashAmount = '',
    this.cashFee = '',
  });

  final bool expanded;
  final bool isBirthday;
  final bool rutTien;
  final String? candleType;
  final bool editingCashAmount;
  final String savedCashAmount;
  final String savedCashFee;
  final String? floorWarning;
  final String notes;
  final String age;
  final String price;
  final String cashAmount;
  final String cashFee;

  WorkItemEditCardState copyWith({
    bool? expanded,
    bool? isBirthday,
    bool? rutTien,
    String? candleType,
    bool? editingCashAmount,
    String? savedCashAmount,
    String? savedCashFee,
    String? floorWarning,
    bool clearFloorWarning = false,
    bool clearCandleType = false,
    String? notes,
    String? age,
    String? price,
    String? cashAmount,
    String? cashFee,
  }) => WorkItemEditCardState(
    expanded: expanded ?? this.expanded,
    isBirthday: isBirthday ?? this.isBirthday,
    rutTien: rutTien ?? this.rutTien,
    candleType: clearCandleType ? null : (candleType ?? this.candleType),
    editingCashAmount: editingCashAmount ?? this.editingCashAmount,
    savedCashAmount: savedCashAmount ?? this.savedCashAmount,
    savedCashFee: savedCashFee ?? this.savedCashFee,
    floorWarning: clearFloorWarning
        ? null
        : (floorWarning ?? this.floorWarning),
    notes: notes ?? this.notes,
    age: age ?? this.age,
    price: price ?? this.price,
    cashAmount: cashAmount ?? this.cashAmount,
    cashFee: cashFee ?? this.cashFee,
  );
}

class WorkItemEditCardNotifier extends Notifier<WorkItemEditCardState> {
  WorkItemEditCardNotifier(this.context);

  final FormDraftContext context;

  /// Seed the initial birthday/candle/rutTien defaults from the work item
  /// being edited. Called once from the widget's `initState` before any
  /// mutation. Updates the state so the seeded values are visible on the
  /// first build.
  void seed({
    required bool isBirthday,
    required bool rutTien,
    String? candleType,
    required String notes,
    required String age,
    required String price,
    required String cashAmount,
    required String cashFee,
  }) {
    if (ref.read(formDraftSessionProvider).containsKey(context)) return;
    final seeded = WorkItemEditCardState(
      isBirthday: isBirthday,
      rutTien: rutTien,
      candleType: candleType,
      notes: notes,
      age: age,
      price: price,
      cashAmount: cashAmount,
      cashFee: cashFee,
    );
    if (state.isBirthday != isBirthday ||
        state.rutTien != rutTien ||
        state.candleType != candleType) {
      state = seeded;
    }
  }

  @override
  WorkItemEditCardState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const WorkItemEditCardState(),
    );
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(context) ?? false) &&
          !next.containsKey(context)) {
        state = const WorkItemEditCardState();
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<WorkItemEditCardState>(context) ??
        const WorkItemEditCardState();
  }

  void _set(WorkItemEditCardState next) {
    state = next;
    ref.read(formDraftSessionProvider.notifier).retainDraft(context, next);
  }

  void toggleExpanded() => _set(state.copyWith(expanded: !state.expanded));

  void setBirthday(bool value, {String? candleDefault}) {
    var candleType = state.candleType;
    if (value && candleType == 'khong_nen' && candleDefault != null) {
      candleType = candleDefault;
    }
    _set(state.copyWith(isBirthday: value, candleType: candleType));
  }

  void setCandleType(String? value) =>
      _set(state.copyWith(candleType: value, clearCandleType: value == null));

  void setRutTien(bool value) =>
      _set(state.copyWith(rutTien: value, editingCashAmount: false));

  void setEditingCashAmount(bool value) =>
      _set(state.copyWith(editingCashAmount: value));

  void setFloorWarning(String? value) => _set(
    state.copyWith(floorWarning: value, clearFloorWarning: value == null),
  );

  void clearFloorWarning() => _set(state.copyWith(clearFloorWarning: true));

  void saveCashAttributes(String amount, String fee) => _set(
    state.copyWith(
      savedCashAmount: amount,
      savedCashFee: fee,
      cashAmount: amount,
      cashFee: fee,
    ),
  );

  void setNotes(String value) => _set(state.copyWith(notes: value));
  void setAge(String value) => _set(state.copyWith(age: value));
  void setPrice(String value) => _set(state.copyWith(price: value));
  void setCashAmount(String value) => _set(state.copyWith(cashAmount: value));
  void setCashFee(String value) => _set(state.copyWith(cashFee: value));

  void markSaved() {
    final current = state;
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    state = current;
  }

  void markSavedIfUnchanged(WorkItemEditCardState? expected) {
    if (expected == null) return;
    final current = state;
    final cleared = ref
        .read(formDraftSessionProvider.notifier)
        .clearDraftIfUnchanged(context, expected);
    if (cleared) state = current;
  }

  void clearDraft() {
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    state = const WorkItemEditCardState();
  }
}

final workItemEditCardProvider =
    NotifierProvider.family<
      WorkItemEditCardNotifier,
      WorkItemEditCardState,
      FormDraftContext
    >(WorkItemEditCardNotifier.new);
