import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the duplicate-merge confirmation dialog (DG-404 Phase 4.7).
///
/// Owns the keep/merge-from direction swap flag previously held as a
/// `setState` field inside `_DuplicateMergeDialogState`.
class DuplicateMergeDialogState {
  const DuplicateMergeDialogState({this.swapped = false});

  final bool swapped;

  DuplicateMergeDialogState copyWith({bool? swapped}) {
    return DuplicateMergeDialogState(swapped: swapped ?? this.swapped);
  }
}

/// `Notifier` that owns the duplicate-merge dialog swap state
/// (DG-404 Phase 4.7). Sync state because the only mutation is the local
/// keep/merge-from direction swap.
class DuplicateMergeDialogNotifier
    extends Notifier<DuplicateMergeDialogState> {
  @override
  DuplicateMergeDialogState build() => const DuplicateMergeDialogState();

  void reset() => state = const DuplicateMergeDialogState();

  void toggleSwap() =>
      state = state.copyWith(swapped: !state.swapped);
}

/// Provider for the duplicate-merge dialog swap state. The widget reads
/// this and calls the notifier's mutator; no `setState` is required.
final duplicateMergeDialogProvider =
    NotifierProvider<DuplicateMergeDialogNotifier, DuplicateMergeDialogState>(
  DuplicateMergeDialogNotifier.new,
);