import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cake-detail body edit-form state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_editing`, `_isBirthday`, `_rutTien`, `_candleType`, and
/// `_editingCashAmount` fields previously mutated via `setState` inside
/// `_CakeDetailBodyState`. The TextEditingController-backed
/// notes/age/price/cash-amount/cash-fee fields stay on the widget
/// (TextEditingController lifecycle is acceptable-use per DG-404
/// guardrails); the notifier owns the business-logic flags that drive
/// rebuilds. The widget reads [cakeDetailBodyProvider] and invokes the
/// notifier's mutators; no `setState` is required.
class CakeDetailBodyState {
  const CakeDetailBodyState({
    this.editing = false,
    this.isBirthday = false,
    this.rutTien = false,
    this.candleType,
    this.editingCashAmount = false,
  });

  final bool editing;
  final bool isBirthday;
  final bool rutTien;
  final String? candleType;
  final bool editingCashAmount;

  CakeDetailBodyState copyWith({
    bool? editing,
    bool? isBirthday,
    bool? rutTien,
    String? candleType,
    bool? editingCashAmount,
  }) =>
      CakeDetailBodyState(
        editing: editing ?? this.editing,
        isBirthday: isBirthday ?? this.isBirthday,
        rutTien: rutTien ?? this.rutTien,
        candleType: candleType ?? this.candleType,
        editingCashAmount: editingCashAmount ?? this.editingCashAmount,
      );
}

class CakeDetailBodyNotifier extends Notifier<CakeDetailBodyState> {
  @override
  CakeDetailBodyState build() => const CakeDetailBodyState();

  /// Enter edit mode. The widget seeds the TextEditingController-backed
  /// fields and the birthday/candle defaults in its `_startEdit` helper
  /// before calling this; the notifier only owns the `editing` rebuild
  /// trigger plus the seeded birthday/candle/rutTien defaults.
  void startEdit({
    bool isBirthday = false,
    bool rutTien = false,
    String? candleType,
  }) =>
      state = CakeDetailBodyState(
        editing: true,
        isBirthday: isBirthday,
        rutTien: rutTien,
        candleType: candleType,
      );

  void cancelEdit() => state = state.copyWith(editing: false);

  void finishEdit() => state = state.copyWith(editing: false);

  void setBirthday(bool value, {String? candleDefault}) {
    var candleType = state.candleType;
    if (value && candleType == 'khong_nen' && candleDefault != null) {
      candleType = candleDefault;
    }
    state = state.copyWith(isBirthday: value, candleType: candleType);
  }

  void setCandleType(String? value) =>
      state = state.copyWith(candleType: value);

  void setRutTien(bool value) => state = state.copyWith(rutTien: value);

  void setEditingCashAmount(bool value) =>
      state = state.copyWith(editingCashAmount: value);

  /// Stepper handler: updates both the editingCashAmount flag and (when the
  /// widget passes a new candle default) the candle type.
  void cashAmountStepper({required bool editing}) =>
      state = state.copyWith(editingCashAmount: editing);
}

final cakeDetailBodyProvider =
    NotifierProvider<CakeDetailBodyNotifier, CakeDetailBodyState>(
        CakeDetailBodyNotifier.new);