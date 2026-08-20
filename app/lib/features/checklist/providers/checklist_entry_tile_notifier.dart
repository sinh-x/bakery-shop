import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Loading-flag state for a single checklist entry tile (DG-404 Phase 4.7).
///
/// Owns the per-entry `_loading` flag previously held as a `setState`
/// field inside `_ChecklistEntryTileState`. Keyed by entry id via a
/// family provider so each tile in the list maintains its own loading
/// state.
class ChecklistEntryTileState {
  const ChecklistEntryTileState({this.loading = false});

  final bool loading;

  ChecklistEntryTileState copyWith({bool? loading}) {
    return ChecklistEntryTileState(loading: loading ?? this.loading);
  }
}

/// `Notifier` that owns the loading flag for a single checklist entry
/// tile (DG-404 Phase 4.7). Keyed by the entry id via a family provider.
class ChecklistEntryTileNotifier extends Notifier<ChecklistEntryTileState> {
  final int entryId;

  ChecklistEntryTileNotifier(this.entryId);

  @override
  ChecklistEntryTileState build() => const ChecklistEntryTileState();

  void setLoading(bool value) =>
      state = state.copyWith(loading: value);
}

/// Family provider for the checklist entry-tile loading state, keyed by
/// entry id.
final checklistEntryTileProvider =
    NotifierProvider.family<ChecklistEntryTileNotifier,
        ChecklistEntryTileState, int>(ChecklistEntryTileNotifier.new);