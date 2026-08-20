import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for one duplicate candidate group row in the finder screen
/// (DG-404 Phase 4.7). Owns the ordered member selection list previously
/// held as a `setState` field inside `_DuplicateGroupTileState`. The
/// selection is keyed by the group key so each tile maintains its own
/// selection state via a family provider.
class DuplicateGroupTileState {
  const DuplicateGroupTileState({
    this.selectedIds = const <int>[],
  });

  /// Ordered selection: first entry = primary (keep), remaining entries =
  /// sources (merge-from).
  final List<int> selectedIds;

  DuplicateGroupTileState copyWith({List<int>? selectedIds}) {
    return DuplicateGroupTileState(
      selectedIds: selectedIds ?? this.selectedIds,
    );
  }
}

/// `Notifier` that owns the selection state for a single duplicate group
/// tile (DG-404 Phase 4.7). Keyed by the group key via a family provider
/// so each tile in the list maintains its own selection.
class DuplicateGroupTileNotifier extends Notifier<DuplicateGroupTileState> {
  final String groupKey;

  DuplicateGroupTileNotifier(this.groupKey);

  @override
  DuplicateGroupTileState build() => const DuplicateGroupTileState();

  /// Drop stale selection ids that no longer exist in the current group
  /// membership (e.g. after a refresh). Called from `didUpdateWidget`.
  void pruneInvalidIds(Set<int> validIds) {
    final next =
        state.selectedIds.where((id) => validIds.contains(id)).toList();
    if (next.length != state.selectedIds.length) {
      state = state.copyWith(selectedIds: next);
    }
  }

  /// Toggle membership selection. Tapping a selected member deselects it;
  /// tapping a new member adds it as a source.
  void toggleMember(int memberId) {
    final next = List<int>.from(state.selectedIds);
    if (next.contains(memberId)) {
      next.remove(memberId);
    } else {
      next.add(memberId);
    }
    state = state.copyWith(selectedIds: next);
  }

  /// Clear the selection after dispatching a merge.
  void clearSelection() => state = const DuplicateGroupTileState();
}

/// Family provider for the duplicate-group tile selection state, keyed by
/// the group key.
final duplicateGroupTileProvider =
    NotifierProvider.family<DuplicateGroupTileNotifier,
    DuplicateGroupTileState, String>(DuplicateGroupTileNotifier.new);