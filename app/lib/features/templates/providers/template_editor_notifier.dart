import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/message_template.dart';

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
  @override
  TemplateEditorState build() => const TemplateEditorState();

  /// Seed the initial form state from the (optional) [MessageTemplate]
  /// being edited and the caller-supplied defaults. Called once from the
  /// screen's `initState` before any mutation. When [template] is `null`
  /// the form starts in create mode using [initialIsSystem].
  void seed(MessageTemplate? template, {required bool initialIsSystem}) {
    if (template == null) {
      state = TemplateEditorState(isSystem: initialIsSystem);
      return;
    }
    state = TemplateEditorState(
      editingId: template.id,
      selectedScenario: template.scenario,
      isActive: template.active,
      isSystem: template.isSystem,
    );
  }

  void setSelectedScenario(String value) =>
      state = state.copyWith(selectedScenario: value);

  void setActive(bool value) => state = state.copyWith(isActive: value);

  void setIsSystem(bool value) => state = state.copyWith(isSystem: value);

  void setSaving(bool value) => state = state.copyWith(saving: value);
}

/// Provider for the template-editor form state. The widget reads this
/// and calls the notifier's mutators; no `setState` is required.
final templateEditorProvider = NotifierProvider<TemplateEditorNotifier,
    TemplateEditorState>(TemplateEditorNotifier.new);