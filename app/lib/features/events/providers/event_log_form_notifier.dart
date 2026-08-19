import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Quick-log form state for recording bakery events from the phone
/// (DG-404 Phase 4.2 / FR2).
///
/// Holds every field previously mutated via `setState` inside
/// `_EventLogFormState`: `selectedType`, `selectedTags`, `customTags`,
/// `showCustomTagField`, `saving`, and locally-picked `selectedPhotos`.
/// The widget reads [eventLogFormProvider] and invokes the notifier's
/// mutators; no `setState` is required.
class EventLogFormState {
  const EventLogFormState({
    this.selectedType = 'note',
    this.selectedTags = const <String>{},
    this.customTags = const <String>[],
    this.showCustomTagField = false,
    this.saving = false,
    this.selectedPhotos = const <XFile>[],
  });

  final String selectedType;
  final Set<String> selectedTags;
  final List<String> customTags;
  final bool showCustomTagField;
  final bool saving;
  final List<XFile> selectedPhotos;

  EventLogFormState copyWith({
    String? selectedType,
    Set<String>? selectedTags,
    List<String>? customTags,
    bool? showCustomTagField,
    bool? saving,
    List<XFile>? selectedPhotos,
  }) {
    return EventLogFormState(
      selectedType: selectedType ?? this.selectedType,
      selectedTags: selectedTags ?? this.selectedTags,
      customTags: customTags ?? this.customTags,
      showCustomTagField: showCustomTagField ?? this.showCustomTagField,
      saving: saving ?? this.saving,
      selectedPhotos: selectedPhotos ?? this.selectedPhotos,
    );
  }
}

/// `Notifier` that owns the quick-log form state (DG-404 Phase 4.2 /
/// FR2). All mutations that previously lived in `setState` closures
/// inside `_EventLogFormState` are now exposed as notifier methods.
/// The widget reads the state via [eventLogFormProvider] and rebuilds
/// on change — no `setState` is required.
class EventLogFormNotifier extends Notifier<EventLogFormState> {
  @override
  EventLogFormState build() => const EventLogFormState();

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

  void setSaving(bool value) => state = state.copyWith(saving: value);

  /// Reset the form to its initial state after a successful submit.
  void reset() => state = const EventLogFormState();
}

/// Provider for the quick-log form state. The widget reads this and
/// calls the notifier's mutators; no `setState` is required.
final eventLogFormProvider =
    NotifierProvider<EventLogFormNotifier, EventLogFormState>(
  EventLogFormNotifier.new,
);