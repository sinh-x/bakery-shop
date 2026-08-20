import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/event_service.dart';
import '../../../data/providers/events_provider.dart';
import '../../../providers/photo_upload_provider.dart';
import '../../../shared/providers/logged_by_provider.dart';
import '../../../shared/widgets/upload_progress_indicator.dart';
import '../providers/event_log_form_notifier.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'quick_log_photo_picker.dart';

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

/// Quick-log form for recording bakery events from the phone.
///
/// Shows a summary field, type ChoiceChips, tag FilterChips,
/// logged-by row, and a submit button. Inline widget — not a dialog.
class EventLogForm extends ConsumerStatefulWidget {
  const EventLogForm({super.key});

  @override
  ConsumerState<EventLogForm> createState() => _EventLogFormState();
}

class _EventLogFormState extends ConsumerState<EventLogForm> {
  final _summaryCtrl = TextEditingController();
  final _customTagCtrl = TextEditingController();
  final _summaryFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Clear any stale upload state from a previous screen navigation
    // (DG-333 Phase 5.6-c1-fix m2) so progress/errors don't leak across
    // screens that share the global photoUploadNotifierProvider. Deferred
    // to a microtask because Riverpod disallows provider mutation during
    // widget life-cycle hooks (initState/build).
    Future.microtask(
      () => ref.read(photoUploadNotifierProvider.notifier).reset(),
    );
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    _customTagCtrl.dispose();
    _summaryFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final summary = _summaryCtrl.text.trim();
    if (summary.isEmpty) return;
    final notifier = ref.read(eventLogFormProvider.notifier);
    final form = ref.read(eventLogFormProvider);
    notifier.setSaving(true);
    try {
      final loggedBy = ref.read(loggedByProvider);
      final createdEvent = await ref.read(eventsProvider.notifier).logEvent(
            summary: summary,
            type: form.selectedType,
            tags: form.selectedTags.toList(),
            loggedBy: loggedBy,
          );
      if (form.selectedPhotos.isNotEmpty && mounted) {
        await _uploadPhotos(createdEvent.id);
      }
      if (mounted) {
        showTopSnackBar(context, EventsLabels.eventLogged);
        _reset();
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.toString());
      }
    } finally {
      if (mounted) notifier.setSaving(false);
    }
  }

  /// Upload locally-picked photos to [eventId] via the shared
  /// [PhotoUploadNotifier] (FR4) so per-photo progress and error states are
  /// surfaced through the [UploadProgressIndicator] (FR1/FR2). Awaited by
  /// [_submit] before `_reset()` runs so the form is not cleared until every
  /// upload reaches a terminal state (FR3 — race condition fix, AC5).
  /// Remaining photos continue after a failure; a snack bar is shown only when
  /// any photo errored.
  Future<void> _uploadPhotos(int eventId) async {
    final upload = ref.read(photoUploadNotifierProvider.notifier);
    final service = ref.read(eventServiceProvider);
    final form = ref.read(eventLogFormProvider);
    await upload.uploadAll(
      form.selectedPhotos,
      (file) => service.uploadEventPhoto(eventId, file),
    );
    if (mounted && ref.read(photoUploadNotifierProvider).hasErrors) {
      showTopSnackBar(context, EventsLabels.eventPhotosUploadFailed);
    }
  }

  void _reset() {
    _summaryCtrl.clear();
    ref.read(eventLogFormProvider.notifier).reset();
    _summaryFocus.requestFocus();
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
    ref
        .read(eventLogFormProvider.notifier)
        .confirmCustomTag(_customTagCtrl.text.trim());
    _customTagCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loggedBy = ref.watch(loggedByProvider);
    final form = ref.watch(eventLogFormProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary field
        TextField(
          controller: _summaryCtrl,
          focusNode: _summaryFocus,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: EventsLabels.eventPrompt,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),

        // Type chips — single-select, equipment highlighted orange
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
                  ref.read(eventLogFormProvider.notifier).setSelectedType(t.value),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),

        // Tag chips — multi-select + inline custom tag
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ..._kStandardTags.map(
              (tag) => FilterChip(
                label: Text(tag.$2),
                selected: form.selectedTags.contains(tag.$1),
                onSelected: (v) => ref
                    .read(eventLogFormProvider.notifier)
                    .toggleTag(tag.$1, selected: v),
              ),
            ),
            ...form.customTags.map(
              (tag) => FilterChip(
                label: Text(tag),
                selected: form.selectedTags.contains(tag),
                onSelected: (v) => ref
                    .read(eventLogFormProvider.notifier)
                    .toggleTag(tag, selected: v),
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
                    ref.read(eventLogFormProvider.notifier).showCustomTagField(),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Photo picker — compact; uploads after event creation (NFR1)
        QuickLogPhotoPicker(
          selectedPhotos: form.selectedPhotos,
          onSelectionChanged: (files) =>
              ref.read(eventLogFormProvider.notifier).setSelectedPhotos(files),
        ),
        UploadProgressIndicator(
          states: ref.watch(photoUploadNotifierProvider).states,
        ),
        const SizedBox(height: 12),

        // Logged-by row
        Row(
          children: [
            const Icon(Icons.person_outline, size: 18),
            const SizedBox(width: 6),
            Text('${EventsLabels.loggedBy}: ', style: theme.textTheme.bodyMedium),
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
        const SizedBox(height: 16),

        // Submit button
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
              : const Text(
                  EventsLabels.logEvent,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
        ),
      ],
    );
  }
}
