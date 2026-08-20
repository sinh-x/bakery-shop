import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/blank.dart';

/// Form state for the blank add/edit bottom sheet (DG-404 Phase 4.4 / FR2).
///
/// Holds every field previously mutated via `setState` inside
/// `_BlankFormState`: `_category` (selected category slug) and the
/// `_saving` flag. Text-controller-backed fields (name/unit/notes) stay
/// on the widget because `TextEditingController` lifecycle is an
/// acceptable-use case (see DG-404 guardrails). The widget reads
/// [blankFormProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class BlankFormState {
  const BlankFormState({this.category = '', this.saving = false});

  final String category;
  final bool saving;

  BlankFormState copyWith({String? category, bool? saving}) =>
      BlankFormState(
        category: category ?? this.category,
        saving: saving ?? this.saving,
      );
}

/// `Notifier` that owns the blank-form state (DG-404 Phase 4.4 / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_BlankFormState` are now exposed as notifier methods. The widget
/// reads the state via [blankFormProvider] and rebuilds on change — no
/// `setState` is required.
class BlankFormNotifier extends Notifier<BlankFormState> {
  @override
  BlankFormState build() => const BlankFormState();

  /// Seed the initial form state from the (optional) [Blank] being
  /// edited. Called once from the sheet's `initState` before any
  /// mutation. When [blank] is `null` the form starts in create mode.
  void seed(Blank? blank) {
    state = BlankFormState(category: blank?.category ?? '');
  }

  void setCategory(String slug) =>
      state = state.copyWith(category: slug);

  void setSaving(bool value) => state = state.copyWith(saving: value);
}

/// Provider for the blank-form state. The sheet reads this and calls
/// the notifier's mutators; no `setState` is required.
final blankFormProvider =
    NotifierProvider<BlankFormNotifier, BlankFormState>(
        BlankFormNotifier.new);