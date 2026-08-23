import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

/// Add/edit blank modal form state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_blankId` and `_submitted` fields previously mutated via
/// `setState` inside `_AddBlankModalState`. The TextEditingController-backed
/// qty/notes fields stay on the widget (TextEditingController lifecycle is
/// acceptable-use per DG-404 guardrails). The widget reads
/// [addBlankModalProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class AddBlankModalState {
  const AddBlankModalState({
    this.blankId,
    this.quantity = '1',
    this.notes = '',
    this.submitted = false,
    this.initialBlankId,
    this.initialQuantity = '1',
    this.initialNotes = '',
  });

  final int? blankId;
  final String quantity;
  final String notes;
  final bool submitted;
  final int? initialBlankId;
  final String initialQuantity;
  final String initialNotes;

  bool get isDirty =>
      blankId != initialBlankId ||
      quantity != initialQuantity ||
      notes != initialNotes;

  AddBlankModalState copyWith({
    int? blankId,
    String? quantity,
    String? notes,
    bool? submitted,
    bool clearBlankId = false,
  }) => AddBlankModalState(
    blankId: clearBlankId ? null : (blankId ?? this.blankId),
    quantity: quantity ?? this.quantity,
    notes: notes ?? this.notes,
    submitted: submitted ?? this.submitted,
    initialBlankId: initialBlankId,
    initialQuantity: initialQuantity,
    initialNotes: initialNotes,
  );
}

class AddBlankModalNotifier extends Notifier<AddBlankModalState> {
  AddBlankModalNotifier(this.context);

  final FormDraftContext context;

  /// Seed the initial blank id (prefill when editing). Called once from the
  /// widget's `initState` before any mutation. Updates the state so the
  /// prefilled value is visible on the first build (the provider's `build()`
  /// runs before this setter when `ref.read(provider.notifier)` is first
  /// accessed, so we must update `state` here rather than only the private
  /// field).
  void seed({
    required int? blankId,
    required String quantity,
    required String notes,
  }) {
    if (ref.read(formDraftSessionProvider).containsKey(context)) return;
    state = AddBlankModalState(
      blankId: blankId,
      quantity: quantity,
      notes: notes,
      initialBlankId: blankId,
      initialQuantity: quantity,
      initialNotes: notes,
    );
  }

  @override
  AddBlankModalState build() {
    ref.listen(
      formDraftSessionEpochProvider,
      (_, _) => state = const AddBlankModalState(),
    );
    ref.listen(formDraftSessionProvider, (previous, next) {
      if ((previous?.containsKey(context) ?? false) &&
          !next.containsKey(context)) {
        state = const AddBlankModalState();
      }
    });
    return ref
            .read(formDraftSessionProvider.notifier)
            .readDraft<AddBlankModalState>(context) ??
        const AddBlankModalState();
  }

  void _set(AddBlankModalState next) {
    state = next;
    final drafts = ref.read(formDraftSessionProvider.notifier);
    if (next.isDirty) {
      drafts.retainDraft(context, next.copyWith(submitted: false));
    } else {
      drafts.clearDraft(context);
    }
  }

  void setBlankId(int? id) => _set(
    state.copyWith(blankId: id, clearBlankId: id == null, submitted: false),
  );

  void setQuantity(String value) => _set(state.copyWith(quantity: value));

  void setNotes(String value) => _set(state.copyWith(notes: value));

  void setSubmitted() => state = state.copyWith(submitted: true);

  void clearSubmitted() => state = state.copyWith(submitted: false);

  void clearDraft() {
    ref.read(formDraftSessionProvider.notifier).clearDraft(context);
    state = AddBlankModalState(
      blankId: state.initialBlankId,
      quantity: state.initialQuantity,
      notes: state.initialNotes,
      initialBlankId: state.initialBlankId,
      initialQuantity: state.initialQuantity,
      initialNotes: state.initialNotes,
    );
  }
}

final addBlankModalProvider =
    NotifierProvider.family<
      AddBlankModalNotifier,
      AddBlankModalState,
      FormDraftContext
    >(AddBlankModalNotifier.new);
