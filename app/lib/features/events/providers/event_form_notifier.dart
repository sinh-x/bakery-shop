import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/models/event.dart';
import '../../../data/models/event_photo.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/models/form_draft_context.dart';

class EventFormDraft {
  const EventFormDraft({
    this.summary = '',
    this.selectedType = 'note',
    this.selectedTags = const <String>{},
    this.customTags = const <String>[],
    this.showCustomTagField = false,
    this.customTagInput = '',
    this.selectedPhotos = const <XFile>[],
    this.existingPhotos = const <EventPhoto>[],
  });

  final String summary;
  final String selectedType;
  final Set<String> selectedTags;
  final List<String> customTags;
  final bool showCustomTagField;
  final String customTagInput;
  final List<XFile> selectedPhotos;
  final List<EventPhoto> existingPhotos;
}

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
    this.newDraft = const EventFormDraft(),
  });

  final String selectedType;
  final Set<String> selectedTags;
  final List<String> customTags;
  final bool showCustomTagField;
  final bool saving;
  final List<XFile> selectedPhotos;
  final List<EventPhoto> existingPhotos;
  final int? editingId;
  final EventFormDraft newDraft;

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
    EventFormDraft? newDraft,
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
      newDraft: newDraft ?? this.newDraft,
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
  EventFormNotifier([this.context]);

  final FormDraftContext? context;
  bool _initialized = false;
  final Map<String, EventFormDraft> _newDrafts = {};
  String _activeDraftKey = 'standalone';

  @override
  EventFormState build() {
    ref.watch(formDraftSessionEpochProvider);
    _newDrafts.clear();
    _activeDraftKey = 'standalone';
    final retained = context == null
        ? null
        : ref
              .read(formDraftSessionProvider.notifier)
              .readDraft<EventFormDraft>(context!);
    _initialized = retained != null;
    final draft = retained ?? const EventFormDraft();
    return EventFormState(
      selectedType: draft.selectedType,
      selectedTags: draft.selectedTags,
      customTags: draft.customTags,
      showCustomTagField: draft.showCustomTagField,
      selectedPhotos: draft.selectedPhotos,
      existingPhotos: draft.existingPhotos,
      editingId: context?.mode == FormDraftMode.edit
          ? int.tryParse(context?.entityId ?? '')
          : null,
      newDraft: draft,
    );
  }

  bool get hasRetainedDraft =>
      context != null &&
      ref.read(formDraftSessionProvider).containsKey(context);
  EventFormDraft get draftSnapshot => state.newDraft;

  bool clearAfterSuccess(EventFormDraft expected) {
    if (context == null) {
      clearNewDraft();
      return true;
    }
    final cleared = ref
        .read(formDraftSessionProvider.notifier)
        .clearDraftIfUnchanged(context!, expected);
    if (cleared) state = const EventFormState();
    return cleared;
  }

  EventFormDraft draftFor(String key) => context == null
      ? _newDrafts[key] ?? const EventFormDraft()
      : state.newDraft;

  /// Seed the initial form state from the (optional) [BakeryEvent] being
  /// edited. Called once from the screen's `initState` before any
  /// mutation. Has no effect when [event] is `null` (add mode) apart
  /// from clearing the editing id.
  void startNew([String draftKey = 'standalone']) {
    if (hasRetainedDraft) return;
    _activeDraftKey = draftKey;
    final draft = draftFor(draftKey);
    state = EventFormState(
      selectedType: draft.selectedType,
      selectedTags: draft.selectedTags,
      customTags: draft.customTags,
      showCustomTagField: draft.showCustomTagField,
      newDraft: draft,
    );
    _initialized = true;
  }

  void startEdit(BakeryEvent event) {
    if (hasRetainedDraft) return;
    state = EventFormState(
      editingId: event.id,
      selectedType: event.type,
      selectedTags: Set<String>.from(event.tags),
      customTags: _extractCustomTags(event.tags),
      newDraft: state.newDraft,
    );
    _initialized = true;
  }

  void clearNewDraft() {
    _newDrafts.remove(_activeDraftKey);
    state = const EventFormState();
    if (context != null) {
      ref.read(formDraftSessionProvider.notifier).clearDraft(context!);
    }
  }

  void _update(EventFormState next) {
    if (next.editing && context == null) {
      state = next;
      return;
    }
    final draft = EventFormDraft(
      summary: next.newDraft.summary,
      selectedType: next.selectedType,
      selectedTags: next.selectedTags,
      customTags: next.customTags,
      showCustomTagField: next.showCustomTagField,
      customTagInput: next.newDraft.customTagInput,
      selectedPhotos: context == null ? const <XFile>[] : next.selectedPhotos,
      existingPhotos: context == null
          ? const <EventPhoto>[]
          : next.existingPhotos,
    );
    _newDrafts[_activeDraftKey] = draft;
    state = next.copyWith(newDraft: draft);
    if (context != null && _initialized) {
      ref.read(formDraftSessionProvider.notifier).retainDraft(context!, draft);
    }
  }

  void setSummary(String value) {
    if (state.editing && context == null) return;
    final draft = EventFormDraft(
      summary: value,
      selectedType: state.selectedType,
      selectedTags: state.selectedTags,
      customTags: state.customTags,
      showCustomTagField: state.showCustomTagField,
      customTagInput: state.newDraft.customTagInput,
      selectedPhotos: state.selectedPhotos,
      existingPhotos: state.existingPhotos,
    );
    _newDrafts[_activeDraftKey] = draft;
    state = state.copyWith(newDraft: draft);
    if (context != null && _initialized) {
      ref.read(formDraftSessionProvider.notifier).retainDraft(context!, draft);
    }
  }

  void setCustomTagInput(String value) {
    if (state.editing && context == null) return;
    final draft = EventFormDraft(
      summary: state.newDraft.summary,
      selectedType: state.selectedType,
      selectedTags: state.selectedTags,
      customTags: state.customTags,
      showCustomTagField: state.showCustomTagField,
      customTagInput: value,
      selectedPhotos: state.selectedPhotos,
      existingPhotos: state.existingPhotos,
    );
    _newDrafts[_activeDraftKey] = draft;
    state = state.copyWith(newDraft: draft);
    if (context != null && _initialized) {
      ref.read(formDraftSessionProvider.notifier).retainDraft(context!, draft);
    }
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

  void addExistingPhotos(List<EventPhoto> photos) => state = state.copyWith(
    existingPhotos: [...state.existingPhotos, ...photos],
  );

  void setSaving(bool value) => state = state.copyWith(saving: value);
}

/// Provider for the event-form state. The widget reads this and calls
/// the notifier's mutators; no `setState` is required.
final eventFormProvider = NotifierProvider<EventFormNotifier, EventFormState>(
  EventFormNotifier.new,
);

final contextualEventFormProvider =
    NotifierProvider.family<
      EventFormNotifier,
      EventFormState,
      FormDraftContext
    >(EventFormNotifier.new);
