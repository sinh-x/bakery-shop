import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    this.rebuildCounter = 0,
  });

  final String selectedValue;
  final String? selectedStaffName;
  final int rebuildCounter;

  CashDrawerSelectorState copyWith({
    String? selectedValue,
    String? selectedStaffName,
    int? rebuildCounter,
    bool clearStaffName = false,
  }) =>
      CashDrawerSelectorState(
        selectedValue: selectedValue ?? this.selectedValue,
        selectedStaffName:
            clearStaffName ? null : (selectedStaffName ?? this.selectedStaffName),
        rebuildCounter: rebuildCounter ?? this.rebuildCounter,
      );
}

class CashDrawerSelectorNotifier extends Notifier<CashDrawerSelectorState> {
  @override
  CashDrawerSelectorState build() => const CashDrawerSelectorState();

  void setSelectedValue(String value) =>
      state = state.copyWith(selectedValue: value, clearStaffName: true);

  void setSelectedStaffName(String? value) =>
      state = state.copyWith(selectedStaffName: value);

  /// Bump the rebuild counter to force a re-render of the staff-picker
  /// validation error (replaces the pre-migration `setState(() {})`).
  void rebuild() =>
      state = state.copyWith(rebuildCounter: state.rebuildCounter + 1);
}

final cashDrawerSelectorProvider =
    NotifierProvider<CashDrawerSelectorNotifier, CashDrawerSelectorState>(
        CashDrawerSelectorNotifier.new);