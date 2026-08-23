import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/message_template.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

class TemplateNewDraft {
  const TemplateNewDraft({
    this.name = '',
    this.body = '',
    this.scenario = 'ask_info',
    this.isActive = true,
    this.isSystem = false,
  });

  final String name;
  final String body;
  final String scenario;
  final bool isActive;
  final bool isSystem;

  TemplateNewDraft copyWith({
    String? name,
    String? body,
    String? scenario,
    bool? isActive,
    bool? isSystem,
  }) => TemplateNewDraft(
    name: name ?? this.name,
    body: body ?? this.body,
    scenario: scenario ?? this.scenario,
    isActive: isActive ?? this.isActive,
    isSystem: isSystem ?? this.isSystem,
  );
}

/// Form state for the template add/edit screen (DG-404 Phase 4.3 / FR2).
///
/// Holds every field previously mutated via `setState` inside
/// `_TemplateEditorScreenState`: `selectedScenario`, `isActive`,
/// `isSystem`, and the `saving` flag. The widget reads
/// [templateEditorProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class TemplateEditorState {
  const TemplateEditorState({
    this.selectedScenario = 'ask_info',
    this.isActive = true,
    this.isSystem = false,
    this.saving = false,
    this.editingId,
  });

  final String selectedScenario;
  final bool isActive;
  final bool isSystem;
  final bool saving;
  final int? editingId;

  bool get editing => editingId != null;

  TemplateEditorState copyWith({
    String? selectedScenario,
    bool? isActive,
    bool? isSystem,
    bool? saving,
    int? editingId,
  }) {
    return TemplateEditorState(
      selectedScenario: selectedScenario ?? this.selectedScenario,
      isActive: isActive ?? this.isActive,
      isSystem: isSystem ?? this.isSystem,
      saving: saving ?? this.saving,
      editingId: editingId ?? this.editingId,
    );
  }
}

/// `Notifier` that owns the template-editor form state (DG-404 Phase 4.3
/// / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_TemplateEditorScreenState` are now exposed as notifier methods. The
/// widget reads the state via [templateEditorProvider] and rebuilds on
/// change — no `setState` is required.
class TemplateEditorNotifier extends Notifier<TemplateEditorState> {
  TemplateEditorNotifier([this.context]);

  final FormDraftContext? context;
  final Map<bool, TemplateNewDraft> _newDrafts = {};
  bool _activeDraftKey = false;
  bool _initialized = false;

  TemplateNewDraft get newDraft => newDraftFor(_activeDraftKey);
  TemplateNewDraft get draftSnapshot => newDraft;

  TemplateNewDraft newDraftFor(bool isSystem) => context == null
      ? _newDrafts[isSystem] ?? TemplateNewDraft(isSystem: isSystem)
      : ref
                .read(formDraftSessionProvider.notifier)
                .readDraft<TemplateNewDraft>(context!) ??
            _newDrafts[isSystem] ??
            TemplateNewDraft(isSystem: isSystem);

  bool get hasRetainedDraft =>
      context != null &&
      ref.read(formDraftSessionProvider).containsKey(context);

  @override
  TemplateEditorState build() {
    ref.watch(formDraftSessionEpochProvider);
    _newDrafts.clear();
    _activeDraftKey = false;
    _initialized = false;
    if (context != null) {
      final retained = ref
          .read(formDraftSessionProvider.notifier)
          .readDraft<TemplateNewDraft>(context!);
      if (retained != null) {
        _activeDraftKey = retained.isSystem;
        _newDrafts[_activeDraftKey] = retained;
        _initialized = true;
        return TemplateEditorState(
          selectedScenario: retained.scenario,
          isActive: retained.isActive,
          isSystem: retained.isSystem,
          editingId: context!.mode == FormDraftMode.edit
              ? int.tryParse(context!.entityId ?? '')
              : null,
        );
      }
    }
    return const TemplateEditorState();
  }

  /// Seed the initial form state from the (optional) [MessageTemplate]
  /// being edited and the caller-supplied defaults. Called once from the
  /// screen's `initState` before any mutation. When [template] is `null`
  /// the form starts in create mode using [initialIsSystem].
  void seed(MessageTemplate? template, {required bool initialIsSystem}) {
    if (hasRetainedDraft) {
      final draft = newDraftFor(initialIsSystem);
      state = TemplateEditorState(
        selectedScenario: draft.scenario,
        isActive: draft.isActive,
        isSystem: draft.isSystem,
        editingId: template?.id,
      );
      return;
    }
    if (template == null) {
      _activeDraftKey = initialIsSystem;
      final draft = newDraftFor(initialIsSystem);
      state = TemplateEditorState(
        selectedScenario: draft.scenario,
        isActive: draft.isActive,
        isSystem: draft.isSystem,
      );
      _initialized = true;
      return;
    }
    if (context != null) {
      _activeDraftKey = initialIsSystem;
      _newDrafts[_activeDraftKey] = TemplateNewDraft(
        name: template.name,
        body: template.body,
        scenario: template.scenario,
        isActive: template.active,
        isSystem: template.isSystem,
      );
    }
    state = TemplateEditorState(
      editingId: template.id,
      selectedScenario: template.scenario,
      isActive: template.active,
      isSystem: template.isSystem,
    );
    _initialized = true;
  }

  void updateNewDraft({String? name, String? body}) {
    _newDrafts[_activeDraftKey] = newDraft.copyWith(name: name, body: body);
    _retain(_newDrafts[_activeDraftKey]!);
  }

  void clearNewDraft() {
    _newDrafts.remove(_activeDraftKey);
    state = TemplateEditorState(isSystem: _activeDraftKey);
    if (context != null) {
      ref.read(formDraftSessionProvider.notifier).clearDraft(context!);
    }
  }

  bool clearAfterSuccess(TemplateNewDraft expected) {
    if (context == null) {
      clearNewDraft();
      return true;
    }
    final cleared = ref
        .read(formDraftSessionProvider.notifier)
        .clearDraftIfUnchanged(context!, expected);
    if (cleared) {
      _newDrafts.remove(_activeDraftKey);
      state = TemplateEditorState(isSystem: _activeDraftKey);
    }
    return cleared;
  }

  void setSelectedScenario(String value) {
    if (!state.editing || context != null) {
      _newDrafts[_activeDraftKey] = newDraft.copyWith(scenario: value);
      _retain(_newDrafts[_activeDraftKey]!);
    }
    state = state.copyWith(selectedScenario: value);
  }

  void setActive(bool value) {
    if (!state.editing || context != null) {
      _newDrafts[_activeDraftKey] = newDraft.copyWith(isActive: value);
      _retain(_newDrafts[_activeDraftKey]!);
    }
    state = state.copyWith(isActive: value);
  }

  void setIsSystem(bool value) {
    if (!state.editing || context != null) {
      _newDrafts[_activeDraftKey] = newDraft.copyWith(isSystem: value);
      _retain(_newDrafts[_activeDraftKey]!);
    }
    state = state.copyWith(isSystem: value);
  }

  void setSaving(bool value) => state = state.copyWith(saving: value);

  void _retain(TemplateNewDraft draft) {
    if (context != null && _initialized) {
      ref.read(formDraftSessionProvider.notifier).retainDraft(context!, draft);
    }
  }
}

/// Provider for the template-editor form state. The widget reads this
/// and calls the notifier's mutators; no `setState` is required.
final templateEditorProvider =
    NotifierProvider<TemplateEditorNotifier, TemplateEditorState>(
      TemplateEditorNotifier.new,
    );

final contextualTemplateEditorProvider =
    NotifierProvider.family<
      TemplateEditorNotifier,
      TemplateEditorState,
      FormDraftContext
    >(TemplateEditorNotifier.new);
