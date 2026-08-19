import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  });

  final bool expanded;
  final bool isBirthday;
  final bool rutTien;
  final String? candleType;
  final bool editingCashAmount;
  final String savedCashAmount;
  final String savedCashFee;
  final String? floorWarning;

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
  }) =>
      WorkItemEditCardState(
        expanded: expanded ?? this.expanded,
        isBirthday: isBirthday ?? this.isBirthday,
        rutTien: rutTien ?? this.rutTien,
        candleType: clearCandleType ? null : (candleType ?? this.candleType),
        editingCashAmount: editingCashAmount ?? this.editingCashAmount,
        savedCashAmount: savedCashAmount ?? this.savedCashAmount,
        savedCashFee: savedCashFee ?? this.savedCashFee,
        floorWarning:
            clearFloorWarning ? null : (floorWarning ?? this.floorWarning),
      );
}

class WorkItemEditCardNotifier extends Notifier<WorkItemEditCardState> {
  final String workItemId;

  bool _seededIsBirthday = false;
  bool _seededRutTien = false;
  String? _seededCandleType;

  WorkItemEditCardNotifier(this.workItemId);

  /// Seed the initial birthday/candle/rutTien defaults from the work item
  /// being edited. Called once from the widget's `initState` before any
  /// mutation. Updates the state so the seeded values are visible on the
  /// first build.
  void seed({
    required bool isBirthday,
    required bool rutTien,
    String? candleType,
  }) {
    _seededIsBirthday = isBirthday;
    _seededRutTien = rutTien;
    _seededCandleType = candleType;
    final seeded = WorkItemEditCardState(
      isBirthday: isBirthday,
      rutTien: rutTien,
      candleType: candleType,
    );
    if (state.isBirthday != isBirthday ||
        state.rutTien != rutTien ||
        state.candleType != candleType) {
      state = seeded;
    }
  }

  @override
  WorkItemEditCardState build() => WorkItemEditCardState(
        isBirthday: _seededIsBirthday,
        rutTien: _seededRutTien,
        candleType: _seededCandleType,
      );

  void toggleExpanded() => state = state.copyWith(expanded: !state.expanded);

  void setBirthday(bool value, {String? candleDefault}) {
    var candleType = state.candleType;
    if (value && candleType == 'khong_nen' && candleDefault != null) {
      candleType = candleDefault;
    }
    state = state.copyWith(isBirthday: value, candleType: candleType);
  }

  void setCandleType(String? value) => state = state.copyWith(candleType: value);

  void setRutTien(bool value) =>
      state = state.copyWith(rutTien: value, editingCashAmount: false);

  void setEditingCashAmount(bool value) =>
      state = state.copyWith(editingCashAmount: value);

  void setFloorWarning(String? value) =>
      state = state.copyWith(floorWarning: value, clearFloorWarning: value == null);

  void clearFloorWarning() =>
      state = state.copyWith(clearFloorWarning: true);

  void saveCashAttributes(String amount, String fee) =>
      state = state.copyWith(savedCashAmount: amount, savedCashFee: fee);
}

final workItemEditCardProvider =
    NotifierProvider.family<WorkItemEditCardNotifier, WorkItemEditCardState, String>(
  WorkItemEditCardNotifier.new,
);