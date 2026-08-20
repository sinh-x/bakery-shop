import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  const BlankStockActionSheetState({this.saving = false});

  final bool saving;

  BlankStockActionSheetState copyWith({bool? saving}) =>
      BlankStockActionSheetState(saving: saving ?? this.saving);
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
  @override
  BlankStockActionSheetState build() =>
      const BlankStockActionSheetState();

  void setSaving(bool value) => state = state.copyWith(saving: value);
}

/// Provider for the blank stock-action-sheet state. The sheet reads
/// this and calls the notifier's mutators; no `setState` is required.
final blankStockActionSheetProvider =
    NotifierProvider<BlankStockActionSheetNotifier,
        BlankStockActionSheetState>(
        BlankStockActionSheetNotifier.new);