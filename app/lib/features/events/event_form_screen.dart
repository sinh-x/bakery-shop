import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

// EXEMPT: 300-line screen threshold exceeded because the event form owns
// type/tag selection, photo upload lifecycle, and submit flow in one screen
// to keep EventFormPhotoSection under its widget limit. Pre-existing at 435
// lines before DG-333 Phase 4 (race-condition fix reduced to 423). Reviewed
// 2026-08-02.
import '../../data/api/event_service.dart';
import '../../data/models/event.dart';
import '../../data/providers/events_provider.dart';
import '../../providers/photo_upload_provider.dart';
import '../../providers/form_draft_session_notifier.dart';
import '../../shared/models/form_draft_context.dart';
import '../../shared/providers/logged_by_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../shared/widgets/upload_progress_indicator.dart';
import '../../shared/widgets/discard_form_draft_action.dart';
import 'providers/event_form_notifier.dart';
import 'widgets/event_form_photo_section.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import '../../data/api/api_client.dart' show apiBaseUrlProvider;

class _EventType {
  const _EventType(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;
}

const _kTypes = [
  _EventType('note', EventsLabels.eventNote, Icons.edit_note),
  _EventType('equipment', EventsLabels.typeEquipment, Icons.warning_amber),
  _EventType('production', EventsLabels.eventProduction, Icons.bakery_dining),
  _EventType('inventory', EventsLabels.eventInventory, Icons.inventory_2),
  _EventType('expense', EventsLabels.eventExpense, Icons.payments),
  _EventType('delivery', EventsLabels.eventDelivery, Icons.local_shipping),
  _EventType('order', EventsLabels.eventOrder, Icons.receipt_long),
];

const _kStandardTags = [
  ('incident', EventsLabels.tagIncident),
  ('knowledge-gap', EventsLabels.tagKnowledgeGap),
  ('maintenance', EventsLabels.tagMaintenance),
  ('equipment', EventsLabels.tagEquipment),
  ('pricing', EventsLabels.tagPricing),
  ('ordering', EventsLabels.tagOrdering),
  ('decoration', EventsLabels.tagDecoration),
  ('staff', EventsLabels.tagStaff),
];

class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({super.key, this.event, this.orderRef, this.orderId});

  final BakeryEvent? event;
  final String? orderRef;
  final int? orderId;

  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen> {
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _customTagCtrl;

  bool get _isEditing => widget.event != null;
  bool get _isOrderLinked => widget.orderId != null;
  String get _draftKey =>
      widget.orderId == null ? 'standalone' : 'order:${widget.orderId}';
  late final FormDraftContext _draftContext;
  NotifierProvider<EventFormNotifier, EventFormState> get _provider =>
      contextualEventFormProvider(_draftContext);

  @override
  void initState() {
    super.initState();
    _draftContext = FormDraftContext(
      formType: 'event',
      mode: _isEditing ? FormDraftMode.edit : FormDraftMode.create,
      entityId: widget.event?.id.toString(),
      optionId: widget.orderId?.toString(),
    );
    // Clear any stale upload state from a previous screen navigation
    // (DG-333 Phase 5.6-c1-fix m2) so progress/errors don't leak across
    // screens that share the global photoUploadNotifierProvider. Deferred
    // to a microtask because Riverpod disallows provider mutation during
    // widget life-cycle hooks (initState/build).
    Future.microtask(
      () => ref.read(photoUploadNotifierProvider.notifier).reset(),
    );
    final e = widget.event;
    final formNotifier = ref.read(_provider.notifier);
    final draft = formNotifier.draftFor(_draftKey);
    final restore = formNotifier.hasRetainedDraft;
    _summaryCtrl = TextEditingController(
      text: restore ? draft.summary : e?.summary ?? '',
    );
    _customTagCtrl = TextEditingController(
      text: e == null ? draft.customTagInput : '',
    );
    _summaryCtrl.addListener(() {
      ref.read(_provider.notifier).setSummary(_summaryCtrl.text);
    });
    _customTagCtrl.addListener(() {
      ref.read(_provider.notifier).setCustomTagInput(_customTagCtrl.text);
    });
    // Defer provider mutations to a microtask because Riverpod disallows
    // provider mutation during widget life-cycle hooks (initState/build).
    Future.microtask(() {
      if (!mounted) return;
      final notifier = ref.read(_provider.notifier);
      if (e == null) {
        notifier.startNew(_draftKey);
      } else {
        notifier.startEdit(e);
        _loadExistingPhotos(e.id);
      }
    });
  }

  Future<void> _loadExistingPhotos(int eventId) async {
    try {
      final service = ref.read(eventServiceProvider);
      final photos = await service.getEventPhotos(eventId);
      if (mounted) {
        ref.read(_provider.notifier).addExistingPhotos(photos);
      }
    } catch (e) {
      debugPrint('_loadExistingPhotos failed: $e');
      // Non-fatal: edit form still works without existing photo display.
    }
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    _customTagCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final summary = _summaryCtrl.text.trim();
    if (summary.isEmpty) return;
    final formNotifier = ref.read(_provider.notifier);
    final form = ref.read(_provider);
    final submittedDraft = formNotifier.draftSnapshot;
    final eventsNotifier = ref.read(eventsProvider.notifier);
    final loggedBy = ref.read(loggedByProvider);
    final upload = ref.read(photoUploadNotifierProvider.notifier);
    final photoService = ref.read(eventServiceProvider);
    final selectedPhotos = List<XFile>.of(form.selectedPhotos);
    formNotifier.setSaving(true);
    try {
      final hasNewPhotos = form.selectedPhotos.isNotEmpty;
      if (_isEditing) {
        await eventsNotifier.updateEvent(
          id: widget.event!.id,
          summary: summary,
          type: form.selectedType,
          tags: form.selectedTags.toList(),
          loggedBy: loggedBy,
        );
        if (hasNewPhotos) {
          await _uploadPhotos(
            widget.event!.id,
            upload,
            photoService,
            selectedPhotos,
          );
        }
        if (mounted) showTopSnackBar(context, EventsLabels.eventUpdated);
      } else {
        final createdEvent = await eventsNotifier.logEvent(
          summary: summary,
          type: form.selectedType,
          tags: form.selectedTags.toList(),
          loggedBy: loggedBy,
          orderId: widget.orderId,
        );

        if (hasNewPhotos) {
          await _uploadPhotos(
            createdEvent.id,
            upload,
            photoService,
            selectedPhotos,
          );
        }
        if (mounted) showTopSnackBar(context, EventsLabels.eventLogged);
      }
      formNotifier.clearAfterSuccess(submittedDraft);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.toString());
      }
    } finally {
      formNotifier.setSaving(false);
    }
  }

  /// Upload locally-picked photos to [eventId] via the shared
  /// [PhotoUploadNotifier] (FR4) so per-photo progress and error states are
  /// surfaced through the [UploadProgressIndicator] (FR1/FR2). Awaited by
  /// [_submit] before `context.pop()` so the screen does not dismiss until
  /// every upload reaches a terminal state (FR3 — race condition fix).
  /// Remaining photos continue after a failure; a snack bar is shown only when
  /// any photo errored.
  Future<void> _uploadPhotos(
    int eventId,
    PhotoUploadNotifier upload,
    EventService service,
    List<XFile> selectedPhotos,
  ) async {
    await upload.uploadAll(
      selectedPhotos,
      (file) => service.uploadEventPhoto(eventId, file),
    );
    if (mounted && ref.read(photoUploadNotifierProvider).hasErrors) {
      showTopSnackBar(context, EventsLabels.eventPhotosUploadFailed);
    }
  }

  Future<void> _changeLogger() async {
    final current = ref.read(loggedByProvider);
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(EventsLabels.loggedBy),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: EventsLabels.setYourName),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(SharedLabels.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text(SharedLabels.save),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty) {
      await ref.read(loggedByProvider.notifier).setName(result);
    }
  }

  void _confirmCustomTag() {
    ref.read(_provider.notifier).confirmCustomTag(_customTagCtrl.text.trim());
    _customTagCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loggedBy = ref.watch(loggedByProvider);
    final form = ref.watch(_provider);

    final title = _isEditing
        ? EventsLabels.editEvent
        : _isOrderLinked
        ? EventsLabels.addOrderIncident
        : EventsLabels.createEvent;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          DiscardFormDraftAction(
            isDirty: ref
                .watch(formDraftSessionProvider)
                .containsKey(_draftContext),
            onDiscard: () {
              ref.read(_provider.notifier).clearNewDraft();
              context.pop();
            },
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isOrderLinked)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '${EventsLabels.orderLabel}: ${widget.orderRef}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _summaryCtrl,
            autofocus: !_isEditing,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: EventsLabels.eventSummary,
              hintText: EventsLabels.eventPrompt,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              EventsLabels.eventType,
              style: theme.textTheme.titleSmall,
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _kTypes.map((t) {
              final selected = form.selectedType == t.value;
              return ChoiceChip(
                label: Text(t.label),
                avatar: Icon(t.icon, size: 16),
                selected: selected,
                selectedColor: t.value == 'equipment'
                    ? Colors.orange.shade100
                    : colorScheme.primaryContainer,
                onSelected: (_) =>
                    ref.read(_provider.notifier).setSelectedType(t.value),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              ProductsLabels.tagsLabel,
              style: theme.textTheme.titleSmall,
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ..._kStandardTags.map(
                (tag) => FilterChip(
                  label: Text(tag.$2),
                  selected: form.selectedTags.contains(tag.$1),
                  onSelected: (v) => ref
                      .read(_provider.notifier)
                      .toggleTag(tag.$1, selected: v),
                ),
              ),
              ...form.customTags.map(
                (tag) => FilterChip(
                  label: Text(tag),
                  selected: form.selectedTags.contains(tag),
                  onSelected: (v) =>
                      ref.read(_provider.notifier).toggleTag(tag, selected: v),
                ),
              ),
              if (form.showCustomTagField)
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _customTagCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: EventsLabels.addTag,
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                    ),
                    onSubmitted: (_) => _confirmCustomTag(),
                  ),
                )
              else
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text(EventsLabels.addTag),
                  onPressed: () =>
                      ref.read(_provider.notifier).showCustomTagField(),
                ),
            ],
          ),
          const SizedBox(height: 24),
          EventFormPhotoSection(
            existingPhotos: form.existingPhotos,
            selectedPhotos: form.selectedPhotos,
            baseUrl: ref.read(apiBaseUrlProvider),
            onSelectionChanged: (files) =>
                ref.read(_provider.notifier).setSelectedPhotos(files),
          ),
          UploadProgressIndicator(
            states: ref.watch(photoUploadNotifierProvider).states,
          ),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 18),
              const SizedBox(width: 6),
              Text(
                '${EventsLabels.loggedBy}: ',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                loggedBy.isNotEmpty ? loggedBy : EventsLabels.setYourName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: loggedBy.isEmpty ? colorScheme.error : null,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _changeLogger,
                child: const Text(EventsLabels.changeLogger),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: form.saving ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: form.saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _isEditing ? SharedLabels.save : EventsLabels.logEvent,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
