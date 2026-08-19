import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Order photo tag-edit sheet state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_selectedTags` and `_saving` fields previously mutated via
/// `setState` inside `_TagEditSheetState`. The widget reads
/// [orderPhotoTagEditProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class OrderPhotoTagEditState {
  const OrderPhotoTagEditState({
    this.selectedTags = const <String>{},
    this.saving = false,
  });

  final Set<String> selectedTags;
  final bool saving;

  OrderPhotoTagEditState copyWith({
    Set<String>? selectedTags,
    bool? saving,
  }) =>
      OrderPhotoTagEditState(
        selectedTags: selectedTags ?? this.selectedTags,
        saving: saving ?? this.saving,
      );
}

class OrderPhotoTagEditNotifier extends Notifier<OrderPhotoTagEditState> {
  @override
  OrderPhotoTagEditState build() => const OrderPhotoTagEditState();

  /// Seed the initial tag set from the photo being edited. Called once from
  /// the widget's `initState` before any mutation. Updates the state so the
  /// seeded tags are visible on the first build.
  void seedTags(Set<String> tags) {
    if (!setEquals(state.selectedTags, tags) || state.saving) {
      state = state.copyWith(selectedTags: Set<String>.from(tags));
    }
  }

  void toggleTag(String tag, bool selected) {
    final next = Set<String>.from(state.selectedTags);
    if (selected) {
      next.add(tag);
    } else {
      next.remove(tag);
    }
    state = state.copyWith(selectedTags: next);
  }

  void setSaving(bool value) => state = state.copyWith(saving: value);
}

final orderPhotoTagEditProvider =
    NotifierProvider<OrderPhotoTagEditNotifier, OrderPhotoTagEditState>(
        OrderPhotoTagEditNotifier.new);