import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Edit/save state for a single BOM row on the BOM mapping screen
/// (DG-404 Phase 4.4 / FR2).
///
/// Owns the `_editing` and `_saving` flags previously mutated via
/// `setState` inside `_BomRowState`. The widget reads
/// [bomRowStateProvider] and invokes the notifier's mutators; no
/// `setState` is required. The provider is keyed by the BOM row id so
/// each row owns an independent state instance. Following the codebase
/// convention for `NotifierProvider.family` (arg as constructor param,
/// matching `bomProvider` / `BomNotifier`).
class BomRowState {
  const BomRowState({this.editing = false, this.saving = false});

  final bool editing;
  final bool saving;

  BomRowState copyWith({bool? editing, bool? saving}) => BomRowState(
        editing: editing ?? this.editing,
        saving: saving ?? this.saving,
      );
}

/// `Notifier` that owns the edit/save state of a single BOM row
/// (DG-404 Phase 4.4 / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_BomRowState` are now exposed as notifier methods. The widget reads
/// the state via [bomRowStateProvider] and rebuilds on change — no
/// `setState` is required.
class BomRowNotifier extends Notifier<BomRowState> {
  final int bomId;

  BomRowNotifier(this.bomId);

  @override
  BomRowState build() => const BomRowState();

  void beginEdit() => state = state.copyWith(editing: true);

  void startSaving() =>
      state = state.copyWith(saving: true, editing: false);

  void finishSaving() => state = state.copyWith(saving: false);
}

/// Family provider keyed by BOM row id. Each BOM row reads its own
/// state instance via `bomRowStateProvider(bom.id)`.
final bomRowStateProvider =
    NotifierProvider.family<BomRowNotifier, BomRowState, int>(
  BomRowNotifier.new,
);