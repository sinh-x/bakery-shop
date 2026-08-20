import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the duplicate-finder screen merge-in-flight guard
/// (DG-404 Phase 4.7). Owns the group key currently in flight previously
/// held as a `setState` field inside `_DuplicateFinderScreenState`. `null`
/// when no merge is running.
class DuplicateFinderScreenState {
  const DuplicateFinderScreenState({this.mergingKey});

  final String? mergingKey;

  DuplicateFinderScreenState copyWith({String? mergingKey}) {
    return DuplicateFinderScreenState(
      mergingKey: mergingKey ?? this.mergingKey,
    );
  }
}

/// `Notifier` that owns the duplicate-finder screen merge-in-flight state
/// (DG-404 Phase 4.7). Sync state because the only mutation is setting or
/// clearing the in-flight group key.
class DuplicateFinderScreenNotifier
    extends Notifier<DuplicateFinderScreenState> {
  @override
  DuplicateFinderScreenState build() => const DuplicateFinderScreenState();

  void setMergingKey(String? key) =>
      state = state.copyWith(mergingKey: key);
}

/// Provider for the duplicate-finder screen merge-in-flight state. The
/// widget reads this and calls the notifier's mutator; no `setState` is
/// required.
final duplicateFinderScreenProvider =
    NotifierProvider<DuplicateFinderScreenNotifier,
    DuplicateFinderScreenState>(DuplicateFinderScreenNotifier.new);