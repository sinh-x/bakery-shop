import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

/// Order photo tag-edit sheet state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_selectedTags` and `_saving` fields previously mutated via
/// `setState` inside `_TagEditSheetState`. The widget reads
/// [orderPhotoTagEditProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class OrderPhotoTagEditState {
  const OrderPhotoTagEditState({
    this.selectedTags = const <String>{},
    this.initialTags = const <String>{},
  });

  final Set<String> selectedTags;
  final Set<String> initialTags;

  bool get isDirty => !setEquals(selectedTags, initialTags);

  OrderPhotoTagEditState copyWith({
    Set<String>? selectedTags,
    Set<String>? initialTags,
  }) => OrderPhotoTagEditState(
    selectedTags: selectedTags ?? this.selectedTags,
    initialTags: initialTags ?? this.initialTags,
  );
}

class OrderPhotoTagEditNotifier extends Notifier<OrderPhotoTagEditState> {
  OrderPhotoTagEditNotifier(this.context);

  final FormDraftContext context;

  @override
  OrderPhotoTagEditState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const OrderPhotoTagEditState(),
    );
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(context) ?? false) &&
          !next.containsKey(context)) {
        state = const OrderPhotoTagEditState();
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<OrderPhotoTagEditState>(context) ??
        const OrderPhotoTagEditState();
  }

  /// Seed the initial tag set from the photo being edited. Called once from
  /// the widget's `initState` before any mutation. Updates the state so the
  /// seeded tags are visible on the first build.
  void seedTags(Set<String> tags) {
    if (ref.read(formDraftSessionProvider).containsKey(context)) return;
    state = OrderPhotoTagEditState(
      selectedTags: Set<String>.from(tags),
      initialTags: Set<String>.from(tags),
    );
  }

  void toggleTag(String tag, bool selected) {
    final next = Set<String>.from(state.selectedTags);
    if (selected) {
      next.add(tag);
    } else {
      next.remove(tag);
    }
    state = state.copyWith(selectedTags: next);
    final drafts = ref.read(formDraftSessionProvider.notifier);
    if (state.isDirty) {
      drafts.retainDraft(context, state);
    } else {
      drafts.clearDraft(context);
    }
  }

  void clearDraft() {
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    state = OrderPhotoTagEditState(
      selectedTags: Set<String>.from(state.initialTags),
      initialTags: Set<String>.from(state.initialTags),
    );
  }
}

final orderPhotoTagEditProvider =
    NotifierProvider.family<
      OrderPhotoTagEditNotifier,
      OrderPhotoTagEditState,
      FormDraftContext
    >(OrderPhotoTagEditNotifier.new);
