import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  const BomAddSheetState({this.selectedBlankId, this.saving = false});

  final int? selectedBlankId;
  final bool saving;

  BomAddSheetState copyWith({int? selectedBlankId, bool? saving}) =>
      BomAddSheetState(
        selectedBlankId: selectedBlankId ?? this.selectedBlankId,
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
  @override
  BomAddSheetState build() => const BomAddSheetState();

  void selectBlank(int? blankId) =>
      state = state.copyWith(selectedBlankId: blankId);

  void setSaving(bool value) => state = state.copyWith(saving: value);
}

/// Provider for the add-BOM-sheet state. The sheet reads this and
/// calls the notifier's mutators; no `setState` is required.
final bomAddSheetProvider =
    NotifierProvider<BomAddSheetNotifier, BomAddSheetState>(
        BomAddSheetNotifier.new);