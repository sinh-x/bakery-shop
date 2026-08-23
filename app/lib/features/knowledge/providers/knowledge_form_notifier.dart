import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/knowledge_entry.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

class KnowledgeNewDraft {
  const KnowledgeNewDraft({
    this.title = '',
    this.content = '',
    this.selectedType = 'note',
    this.selectedTags = const <String>{},
    this.pinAfterSave = false,
    this.photos = const <KnowledgeFormPhotoEntry>[],
  });

  final String title;
  final String content;
  final String selectedType;
  final Set<String> selectedTags;
  final bool pinAfterSave;
  final List<KnowledgeFormPhotoEntry> photos;

  KnowledgeNewDraft copyWith({
    String? title,
    String? content,
    String? selectedType,
    Set<String>? selectedTags,
    bool? pinAfterSave,
    List<KnowledgeFormPhotoEntry>? photos,
  }) => KnowledgeNewDraft(
    title: title ?? this.title,
    content: content ?? this.content,
    selectedType: selectedType ?? this.selectedType,
    selectedTags: selectedTags ?? this.selectedTags,
    pinAfterSave: pinAfterSave ?? this.pinAfterSave,
    photos: photos ?? this.photos,
  );
}

/// Internal helper to track a photo (either existing or new local file)
/// used by the knowledge add/edit screen.
class KnowledgeFormPhotoEntry {
  const KnowledgeFormPhotoEntry({this.photo, this.file});

  final KnowledgePhoto? photo;
  final XFile? file;
}

/// Form state for the knowledge add/edit screen (DG-404 Phase 4.7 / FR2).
///
/// Holds every field previously mutated via `setState` inside
/// `_KnowledgeFormScreenState`: `selectedType`, `selectedTags`,
/// `showTagField`, `saving`, `pinAfterSave`, and the local `photos`
/// list (existing + picked entries). The widget reads
/// [knowledgeFormProvider] and invokes the notifier's mutators; no
/// `setState` is required.
class KnowledgeFormState {
  const KnowledgeFormState({
    this.selectedType = 'note',
    this.selectedTags = const <String>{},
    this.showTagField = false,
    this.saving = false,
    this.pinAfterSave = false,
    this.photos = const <KnowledgeFormPhotoEntry>[],
    this.editingId,
  });

  final String selectedType;
  final Set<String> selectedTags;
  final bool showTagField;
  final bool saving;
  final bool pinAfterSave;
  final List<KnowledgeFormPhotoEntry> photos;
  final int? editingId;

  bool get editing => editingId != null;

  KnowledgeFormState copyWith({
    String? selectedType,
    Set<String>? selectedTags,
    bool? showTagField,
    bool? saving,
    bool? pinAfterSave,
    List<KnowledgeFormPhotoEntry>? photos,
    int? editingId,
  }) {
    return KnowledgeFormState(
      selectedType: selectedType ?? this.selectedType,
      selectedTags: selectedTags ?? this.selectedTags,
      showTagField: showTagField ?? this.showTagField,
      saving: saving ?? this.saving,
      pinAfterSave: pinAfterSave ?? this.pinAfterSave,
      photos: photos ?? this.photos,
      editingId: editingId ?? this.editingId,
    );
  }
}

/// `Notifier` that owns the knowledge-form state (DG-404 Phase 4.7 /
/// FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_KnowledgeFormScreenState` are now exposed as notifier methods. The
/// widget reads the state via [knowledgeFormProvider] and rebuilds on
/// change — no `setState` is required.
class KnowledgeFormNotifier extends Notifier<KnowledgeFormState> {
  KnowledgeFormNotifier([this.context]);

  final FormDraftContext? context;
  KnowledgeNewDraft _newDraft = const KnowledgeNewDraft();
  bool _initialized = false;

  KnowledgeNewDraft get newDraft => _newDraft;
  KnowledgeNewDraft get draftSnapshot => _newDraft;
  bool get hasRetainedDraft =>
      context != null &&
      ref.read(formDraftSessionProvider).containsKey(context);

  @override
  KnowledgeFormState build() {
    ref.watch(formDraftSessionEpochProvider);
    _newDraft = const KnowledgeNewDraft();
    _initialized = false;
    if (context != null) {
      final retained = ref
          .read(formDraftSessionProvider.notifier)
          .readDraft<KnowledgeNewDraft>(context!);
      _newDraft = retained ?? const KnowledgeNewDraft();
      _initialized = retained != null;
    }
    return KnowledgeFormState(
      selectedType: _newDraft.selectedType,
      selectedTags: _newDraft.selectedTags,
      pinAfterSave: _newDraft.pinAfterSave,
      photos: _newDraft.photos,
      editingId: context?.mode == FormDraftMode.edit
          ? int.tryParse(context?.entityId ?? '')
          : null,
    );
  }

  /// Seed the initial form state from the (optional) [KnowledgeEntry]
  /// being edited. Called once from the screen's `initState` before any
  /// mutation. Has no effect when [entry] is `null` (add mode) apart
  /// from clearing the editing id.
  void seed(KnowledgeEntry? entry) {
    if (hasRetainedDraft) return;
    if (entry == null) {
      state = KnowledgeFormState(
        selectedType: _newDraft.selectedType,
        selectedTags: _newDraft.selectedTags,
        pinAfterSave: _newDraft.pinAfterSave,
      );
      _initialized = true;
      return;
    }
    if (context != null) {
      _newDraft = KnowledgeNewDraft(
        title: entry.title,
        content: entry.content,
        selectedType: entry.type,
        selectedTags: Set<String>.from(entry.tags),
        photos: entry.photos
            .map((photo) => KnowledgeFormPhotoEntry(photo: photo))
            .toList(),
      );
    }
    state = KnowledgeFormState(
      editingId: entry.id,
      selectedType: entry.type,
      selectedTags: Set<String>.from(entry.tags),
      photos: entry.photos
          .map((photo) => KnowledgeFormPhotoEntry(photo: photo))
          .toList(),
    );
    _initialized = true;
  }

  void updateNewDraft({String? title, String? content}) {
    _newDraft = _newDraft.copyWith(title: title, content: content);
    _retain();
  }

  void clearNewDraft() {
    _newDraft = const KnowledgeNewDraft();
    state = const KnowledgeFormState();
    if (context != null && _initialized) {
      ref.read(formDraftSessionProvider.notifier).clearDraft(context!);
    }
  }

  bool clearAfterSuccess(KnowledgeNewDraft expected) {
    if (context == null) {
      clearNewDraft();
      return true;
    }
    final cleared = ref
        .read(formDraftSessionProvider.notifier)
        .clearDraftIfUnchanged(context!, expected);
    if (cleared) {
      _newDraft = const KnowledgeNewDraft();
      state = const KnowledgeFormState();
    }
    return cleared;
  }

  void setSelectedType(String value) => _setSelectedType(value);

  void _setSelectedType(String value) {
    if (!state.editing || context != null) {
      _newDraft = _newDraft.copyWith(selectedType: value);
      _retain();
    }
    state = state.copyWith(selectedType: value);
  }

  void addTag(String tag) {
    final next = Set<String>.from(state.selectedTags)..add(tag);
    if (!state.editing || context != null) {
      _newDraft = _newDraft.copyWith(selectedTags: next);
      _retain();
    }
    state = state.copyWith(selectedTags: next, showTagField: false);
  }

  void removeTag(String tag) {
    final next = Set<String>.from(state.selectedTags)..remove(tag);
    if (!state.editing || context != null) {
      _newDraft = _newDraft.copyWith(selectedTags: next);
      _retain();
    }
    state = state.copyWith(selectedTags: next);
  }

  void showTagField() => state = state.copyWith(showTagField: true);

  void hideTagField() => state = state.copyWith(showTagField: false);

  void addPhotos(List<KnowledgeFormPhotoEntry> entries) {
    final photos = [...state.photos, ...entries];
    _newDraft = _newDraft.copyWith(photos: photos);
    _retain();
    state = state.copyWith(photos: photos);
  }

  void removePhotoAt(int index) {
    final next = List<KnowledgeFormPhotoEntry>.from(state.photos);
    if (index >= 0 && index < next.length) next.removeAt(index);
    _newDraft = _newDraft.copyWith(photos: next);
    _retain();
    state = state.copyWith(photos: next);
  }

  void setPinAfterSave(bool value) {
    if (!state.editing || context != null) {
      _newDraft = _newDraft.copyWith(pinAfterSave: value);
      _retain();
    }
    state = state.copyWith(pinAfterSave: value);
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

/// Provider for the knowledge-form state. The widget reads this and
/// calls the notifier's mutators; no `setState` is required.
final knowledgeFormProvider =
    NotifierProvider<KnowledgeFormNotifier, KnowledgeFormState>(
      KnowledgeFormNotifier.new,
    );

final contextualKnowledgeFormProvider =
    NotifierProvider.family<
      KnowledgeFormNotifier,
      KnowledgeFormState,
      FormDraftContext
    >(KnowledgeFormNotifier.new);
