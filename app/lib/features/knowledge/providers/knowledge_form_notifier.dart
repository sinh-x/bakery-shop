import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/knowledge_entry.dart';

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
  @override
  KnowledgeFormState build() => const KnowledgeFormState();

  /// Seed the initial form state from the (optional) [KnowledgeEntry]
  /// being edited. Called once from the screen's `initState` before any
  /// mutation. Has no effect when [entry] is `null` (add mode) apart
  /// from clearing the editing id.
  void seed(KnowledgeEntry? entry) {
    if (entry == null) {
      state = const KnowledgeFormState();
      return;
    }
    state = KnowledgeFormState(
      editingId: entry.id,
      selectedType: entry.type,
      selectedTags: Set<String>.from(entry.tags),
      photos: entry.photos
          .map((photo) => KnowledgeFormPhotoEntry(photo: photo))
          .toList(),
    );
  }

  void setSelectedType(String value) =>
      state = state.copyWith(selectedType: value);

  void addTag(String tag) {
    final next = Set<String>.from(state.selectedTags)..add(tag);
    state = state.copyWith(
      selectedTags: next,
      showTagField: false,
    );
  }

  void removeTag(String tag) {
    final next = Set<String>.from(state.selectedTags)..remove(tag);
    state = state.copyWith(selectedTags: next);
  }

  void showTagField() => state = state.copyWith(showTagField: true);

  void hideTagField() => state = state.copyWith(showTagField: false);

  void addPhotos(List<KnowledgeFormPhotoEntry> entries) =>
      state = state.copyWith(photos: [...state.photos, ...entries]);

  void removePhotoAt(int index) {
    final next = List<KnowledgeFormPhotoEntry>.from(state.photos);
    if (index >= 0 && index < next.length) next.removeAt(index);
    state = state.copyWith(photos: next);
  }

  void setPinAfterSave(bool value) =>
      state = state.copyWith(pinAfterSave: value);

  void setSaving(bool value) => state = state.copyWith(saving: value);
}

/// Provider for the knowledge-form state. The widget reads this and
/// calls the notifier's mutators; no `setState` is required.
final knowledgeFormProvider =
    NotifierProvider<KnowledgeFormNotifier, KnowledgeFormState>(
        KnowledgeFormNotifier.new);