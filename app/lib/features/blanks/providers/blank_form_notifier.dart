import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/blank.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

class BlankNewDraft {
  const BlankNewDraft({
    this.name = '',
    this.category = '',
    this.unit = '',
    this.notes = '',
  });

  final String name;
  final String category;
  final String unit;
  final String notes;

  BlankNewDraft copyWith({
    String? name,
    String? category,
    String? unit,
    String? notes,
  }) => BlankNewDraft(
    name: name ?? this.name,
    category: category ?? this.category,
    unit: unit ?? this.unit,
    notes: notes ?? this.notes,
  );
}

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
  const BlankFormState({
    this.category = '',
    this.saving = false,
    this.editing = false,
  });

  final String category;
  final bool saving;
  final bool editing;

  BlankFormState copyWith({String? category, bool? saving, bool? editing}) =>
      BlankFormState(
        category: category ?? this.category,
        saving: saving ?? this.saving,
        editing: editing ?? this.editing,
      );
}

/// `Notifier` that owns the blank-form state (DG-404 Phase 4.4 / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_BlankFormState` are now exposed as notifier methods. The widget
/// reads the state via [blankFormProvider] and rebuilds on change — no
/// `setState` is required.
class BlankFormNotifier extends Notifier<BlankFormState> {
  BlankFormNotifier([this.context]);

  final FormDraftContext? context;
  BlankNewDraft _newDraft = const BlankNewDraft();
  bool _initialized = false;

  BlankNewDraft get newDraft => _newDraft;
  BlankNewDraft get draftSnapshot => _newDraft;
  bool get hasRetainedDraft =>
      context != null &&
      ref.read(formDraftSessionProvider).containsKey(context);

  @override
  BlankFormState build() {
    ref.watch(formDraftSessionEpochProvider);
    _newDraft = const BlankNewDraft();
    _initialized = false;
    if (context != null) {
      final retained = ref
          .read(formDraftSessionProvider.notifier)
          .readDraft<BlankNewDraft>(context!);
      _newDraft = retained ?? const BlankNewDraft();
      _initialized = retained != null;
    }
    return BlankFormState(
      category: _newDraft.category,
      editing: context?.mode == FormDraftMode.edit,
    );
  }

  /// Seed the initial form state from the (optional) [Blank] being
  /// edited. Called once from the sheet's `initState` before any
  /// mutation. When [blank] is `null` the form starts in create mode.
  void seed(Blank? blank) {
    if (hasRetainedDraft) return;
    if (blank != null && context != null) {
      _newDraft = BlankNewDraft(
        name: blank.name,
        category: blank.category,
        unit: blank.unit,
        notes: blank.notes,
      );
    }
    state = BlankFormState(
      category: blank?.category ?? _newDraft.category,
      editing: blank != null,
    );
    _initialized = true;
  }

  void updateNewDraft({String? name, String? unit, String? notes}) {
    _newDraft = _newDraft.copyWith(name: name, unit: unit, notes: notes);
    _retain();
  }

  void clearNewDraft() {
    _newDraft = const BlankNewDraft();
    state = const BlankFormState();
    if (context != null && _initialized) {
      ref.read(formDraftSessionProvider.notifier).clearDraft(context!);
    }
  }

  bool clearAfterSuccess(BlankNewDraft expected) {
    if (context == null) {
      clearNewDraft();
      return true;
    }
    final cleared = ref
        .read(formDraftSessionProvider.notifier)
        .clearDraftIfUnchanged(context!, expected);
    if (cleared) {
      _newDraft = const BlankNewDraft();
      state = const BlankFormState();
    }
    return cleared;
  }

  void setCategory(String slug) {
    if (!state.editing || context != null) {
      _newDraft = _newDraft.copyWith(category: slug);
      _retain();
    }
    state = state.copyWith(category: slug);
  }

  void setSaving(bool value) => state = state.copyWith(saving: value);

  void _retain() {
    if (context != null) {
      ref
          .read(formDraftSessionProvider.notifier)
          .retainDraft(context!, _newDraft);
    }
  }
}

/// Provider for the blank-form state. The sheet reads this and calls
/// the notifier's mutators; no `setState` is required.
final blankFormProvider = NotifierProvider<BlankFormNotifier, BlankFormState>(
  BlankFormNotifier.new,
);

final contextualBlankFormProvider =
    NotifierProvider.family<
      BlankFormNotifier,
      BlankFormState,
      FormDraftContext
    >(BlankFormNotifier.new);
