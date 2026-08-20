import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/event.dart';
import '../../../data/models/event_photo.dart';

/// Form state for the event add/edit screen (DG-404 Phase 4.2 / FR2).
///
/// Holds every field previously mutated via `setState` inside
/// `_EventFormScreenState`: `selectedType`, `selectedTags`, `customTags`,
/// `showCustomTagField`, `saving`, locally-picked `selectedPhotos`, and
/// edit-mode `existingPhotos`. The widget reads [eventFormProvider] and
/// invokes the notifier's mutators; no `setState` is required.
class EventFormState {
  const EventFormState({
    this.selectedType = 'note',
    this.selectedTags = const <String>{},
    this.customTags = const <String>[],
    this.showCustomTagField = false,
    this.saving = false,
    this.selectedPhotos = const <XFile>[],
    this.existingPhotos = const <EventPhoto>[],
    this.editingId,
  });

  final String selectedType;
  final Set<String> selectedTags;
  final List<String> customTags;
  final bool showCustomTagField;
  final bool saving;
  final List<XFile> selectedPhotos;
  final List<EventPhoto> existingPhotos;
  final int? editingId;

  bool get editing => editingId != null;

  EventFormState copyWith({
    String? selectedType,
    Set<String>? selectedTags,
    List<String>? customTags,
    bool? showCustomTagField,
    bool? saving,
    List<XFile>? selectedPhotos,
    List<EventPhoto>? existingPhotos,
    int? editingId,
  }) {
    return EventFormState(
      selectedType: selectedType ?? this.selectedType,
      selectedTags: selectedTags ?? this.selectedTags,
      customTags: customTags ?? this.customTags,
      showCustomTagField: showCustomTagField ?? this.showCustomTagField,
      saving: saving ?? this.saving,
      selectedPhotos: selectedPhotos ?? this.selectedPhotos,
      existingPhotos: existingPhotos ?? this.existingPhotos,
      editingId: editingId ?? this.editingId,
    );
  }
}

/// `Notifier` that owns the event-form state (DG-404 Phase 4.2 / FR2).
///
/// All mutations that previously lived in `setState` closures inside
/// `_EventFormScreenState` are now exposed as notifier methods. The
/// widget reads the state via [eventFormProvider] and rebuilds on
/// change — no `setState` is required.
class EventFormNotifier extends Notifier<EventFormState> {
  @override
  EventFormState build() => const EventFormState();

  /// Seed the initial form state from the (optional) [BakeryEvent] being
  /// edited. Called once from the screen's `initState` before any
  /// mutation. Has no effect when [event] is `null` (add mode) apart
  /// from clearing the editing id.
  void seed(BakeryEvent? event) {
    if (event == null) {
      state = const EventFormState();
      return;
    }
    state = EventFormState(
      editingId: event.id,
      selectedType: event.type,
      selectedTags: Set<String>.from(event.tags),
      customTags: _extractCustomTags(event.tags),
    );
  }

  List<String> _extractCustomTags(List<String> tags) {
    const standardTagValues = <String>{
      'incident',
      'knowledge-gap',
      'maintenance',
      'equipment',
      'pricing',
      'ordering',
      'decoration',
      'staff',
    };
    return tags.where((t) => !standardTagValues.contains(t)).toList();
  }

  void setSelectedType(String value) =>
      state = state.copyWith(selectedType: value);

  void toggleTag(String tag, {required bool selected}) {
    final next = Set<String>.from(state.selectedTags);
    if (selected) {
      next.add(tag);
    } else {
      next.remove(tag);
    }
    state = state.copyWith(selectedTags: next);
  }

  void confirmCustomTag(String tag) {
    if (tag.isEmpty) {
      state = state.copyWith(showCustomTagField: false);
      return;
    }
    final customTags = List<String>.from(state.customTags);
    if (!customTags.contains(tag)) customTags.add(tag);
    final selectedTags = Set<String>.from(state.selectedTags)..add(tag);
    state = state.copyWith(
      customTags: customTags,
      selectedTags: selectedTags,
      showCustomTagField: false,
    );
  }

  void cancelCustomTag() =>
      state = state.copyWith(showCustomTagField: false);

  void showCustomTagField() =>
      state = state.copyWith(showCustomTagField: true);

  void setSelectedPhotos(List<XFile> files) =>
      state = state.copyWith(selectedPhotos: files);

  void addExistingPhotos(List<EventPhoto> photos) => state = state.copyWith(
        existingPhotos: [...state.existingPhotos, ...photos],
      );

  void setSaving(bool value) => state = state.copyWith(saving: value);
}

/// Provider for the event-form state. The widget reads this and calls
/// the notifier's mutators; no `setState` is required.
final eventFormProvider =
    NotifierProvider<EventFormNotifier, EventFormState>(EventFormNotifier.new);