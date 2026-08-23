import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

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
    this.summary = '',
    this.customTagInput = '',
  });

  final String selectedType;
  final Set<String> selectedTags;
  final List<String> customTags;
  final bool showCustomTagField;
  final bool saving;
  final List<XFile> selectedPhotos;
  final String summary;
  final String customTagInput;

  EventLogFormState copyWith({
    String? selectedType,
    Set<String>? selectedTags,
    List<String>? customTags,
    bool? showCustomTagField,
    bool? saving,
    List<XFile>? selectedPhotos,
    String? summary,
    String? customTagInput,
  }) {
    return EventLogFormState(
      selectedType: selectedType ?? this.selectedType,
      selectedTags: selectedTags ?? this.selectedTags,
      customTags: customTags ?? this.customTags,
      showCustomTagField: showCustomTagField ?? this.showCustomTagField,
      saving: saving ?? this.saving,
      selectedPhotos: selectedPhotos ?? this.selectedPhotos,
      summary: summary ?? this.summary,
      customTagInput: customTagInput ?? this.customTagInput,
    );
  }
}

/// `Notifier` that owns the quick-log form state (DG-404 Phase 4.2 /
/// FR2). All mutations that previously lived in `setState` closures
/// inside `_EventLogFormState` are now exposed as notifier methods.
/// The widget reads the state via [eventLogFormProvider] and rebuilds
/// on change — no `setState` is required.
class EventLogFormNotifier extends Notifier<EventLogFormState> {
  EventLogFormNotifier([this.context]);

  final FormDraftContext? context;
  EventLogFormState get draftSnapshot => state.copyWith(saving: false);
  @override
  EventLogFormState build() {
    ref.watch(formDraftSessionEpochProvider);
    return context == null
        ? const EventLogFormState()
        : ref
                  .read(formDraftSessionProvider.notifier)
                  .readDraft<EventLogFormState>(context!) ??
              const EventLogFormState();
  }

  void setSelectedType(String value) =>
      _update(state.copyWith(selectedType: value));

  void toggleTag(String tag, {required bool selected}) {
    final next = Set<String>.from(state.selectedTags);
    if (selected) {
      next.add(tag);
    } else {
      next.remove(tag);
    }
    _update(state.copyWith(selectedTags: next));
  }

  void confirmCustomTag(String tag) {
    if (tag.isEmpty) {
      _update(state.copyWith(showCustomTagField: false));
      return;
    }
    final customTags = List<String>.from(state.customTags);
    if (!customTags.contains(tag)) customTags.add(tag);
    final selectedTags = Set<String>.from(state.selectedTags)..add(tag);
    _update(
      state.copyWith(
        customTags: customTags,
        selectedTags: selectedTags,
        showCustomTagField: false,
      ),
    );
  }

  void cancelCustomTag() => _update(state.copyWith(showCustomTagField: false));

  void showCustomTagField() =>
      _update(state.copyWith(showCustomTagField: true));

  void setSelectedPhotos(List<XFile> files) =>
      _update(state.copyWith(selectedPhotos: files));

  void setSummary(String value) => _update(state.copyWith(summary: value));

  void setCustomTagInput(String value) =>
      _update(state.copyWith(customTagInput: value));

  void setSaving(bool value) => state = state.copyWith(saving: value);

  /// Reset the form to its initial state after a successful submit.
  void reset() {
    state = const EventLogFormState();
    if (context != null) {
      ref.read(formDraftSessionProvider.notifier).clearDraft(context!);
    }
  }

  bool clearAfterSuccess(EventLogFormState expected) {
    if (context == null) {
      reset();
      return true;
    }
    final cleared = ref
        .read(formDraftSessionProvider.notifier)
        .clearDraftIfUnchanged(context!, expected);
    if (cleared) state = const EventLogFormState();
    return cleared;
  }

  void _update(EventLogFormState next) {
    state = next;
    if (context != null) {
      ref
          .read(formDraftSessionProvider.notifier)
          .retainDraft(context!, next.copyWith(saving: false));
    }
  }
}

/// Provider for the quick-log form state. The widget reads this and
/// calls the notifier's mutators; no `setState` is required.
final eventLogFormProvider =
    NotifierProvider<EventLogFormNotifier, EventLogFormState>(
      EventLogFormNotifier.new,
    );

final contextualEventLogFormProvider =
    NotifierProvider.family<
      EventLogFormNotifier,
      EventLogFormState,
      FormDraftContext
    >(EventLogFormNotifier.new);
