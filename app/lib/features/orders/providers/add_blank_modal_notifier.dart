import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    this.submitted = false,
  });

  final int? blankId;
  final bool submitted;

  AddBlankModalState copyWith({
    int? blankId,
    bool? submitted,
  }) =>
      AddBlankModalState(
        blankId: blankId ?? this.blankId,
        submitted: submitted ?? this.submitted,
      );
}

class AddBlankModalNotifier extends Notifier<AddBlankModalState> {
  int? _initialBlankId;

  /// Seed the initial blank id (prefill when editing). Called once from the
  /// widget's `initState` before any mutation. Updates the state so the
  /// prefilled value is visible on the first build (the provider's `build()`
  /// runs before this setter when `ref.read(provider.notifier)` is first
  /// accessed, so we must update `state` here rather than only the private
  /// field).
  void seedInitialBlankId(int? blankId) {
    _initialBlankId = blankId;
    if (state.blankId != blankId) {
      state = state.copyWith(blankId: blankId);
    }
  }

  @override
  AddBlankModalState build() =>
      AddBlankModalState(blankId: _initialBlankId);

  void setBlankId(int? id) =>
      state = state.copyWith(blankId: id, submitted: false);

  void setSubmitted() => state = state.copyWith(submitted: true);

  void clearSubmitted() => state = state.copyWith(submitted: false);
}

final addBlankModalProvider =
    NotifierProvider<AddBlankModalNotifier, AddBlankModalState>(
        AddBlankModalNotifier.new);