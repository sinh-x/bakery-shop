import 'dart:io';

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
import '../../data/models/event_photo.dart';
import '../../providers/events_provider.dart';
import '../../providers/photo_upload_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../shared/widgets/upload_progress_indicator.dart';
import 'widgets/event_form_photo_section.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

import '../../data/api/api_client.dart' show apiBaseUrlProvider;

class _EventType {
  const _EventType(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;
}

const _kTypes = [
  _EventType('note', VN.eventNote, Icons.edit_note),
  _EventType('equipment', VN.typeEquipment, Icons.warning_amber),
  _EventType('production', VN.eventProduction, Icons.bakery_dining),
  _EventType('inventory', VN.eventInventory, Icons.inventory_2),
  _EventType('expense', VN.eventExpense, Icons.payments),
  _EventType('delivery', VN.eventDelivery, Icons.local_shipping),
  _EventType('order', VN.eventOrder, Icons.receipt_long),
];

const _kStandardTags = [
  ('incident', VN.tagIncident),
  ('knowledge-gap', VN.tagKnowledgeGap),
  ('maintenance', VN.tagMaintenance),
  ('equipment', VN.tagEquipment),
  ('pricing', VN.tagPricing),
  ('ordering', VN.tagOrdering),
  ('decoration', VN.tagDecoration),
  ('staff', VN.tagStaff),
];

class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({
    super.key,
    this.event,
    this.orderRef,
    this.orderId,
  });

  final BakeryEvent? event;
  final String? orderRef;
  final int? orderId;

  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen> {
  late final TextEditingController _summaryCtrl;
  final _customTagCtrl = TextEditingController();

  late String _selectedType;
  late final Set<String> _selectedTags;
  final _customTags = <String>[];
  bool _showCustomTagField = false;
  bool _saving = false;

  final _selectedPhotos = <XFile>[];
  final _existingPhotos = <EventPhoto>[];

  bool get _isEditing => widget.event != null;
  bool get _isOrderLinked => widget.orderId != null;

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
    final e = widget.event;
    _summaryCtrl = TextEditingController(text: e?.summary ?? '');
    _selectedType = e?.type ?? 'note';
    _selectedTags = Set<String>.from(e?.tags ?? []);
    if (e != null) {
      final standardTagValues = _kStandardTags.map((t) => t.$1).toSet();
      for (final tag in e.tags) {
        if (!standardTagValues.contains(tag)) {
          _customTags.add(tag);
        }
      }
      _loadExistingPhotos(e.id);
    }
  }

  Future<void> _loadExistingPhotos(int eventId) async {
    try {
      final service = ref.read(eventServiceProvider);
      final photos = await service.getEventPhotos(eventId);
      if (mounted) setState(() => _existingPhotos.addAll(photos));
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

    setState(() => _saving = true);
    try {
      final loggedBy = ref.read(loggedByProvider);
      final hasNewPhotos = _selectedPhotos.isNotEmpty;
      final upload = ref.read(photoUploadNotifierProvider.notifier);
      if (_isEditing) {
        await ref
            .read(eventsProvider.notifier)
            .updateEvent(
              id: widget.event!.id,
              summary: summary,
              type: _selectedType,
              tags: _selectedTags.toList(),
              loggedBy: loggedBy,
            );
        if (hasNewPhotos && mounted) {
          await _uploadPhotos(widget.event!.id, upload);
        }
        if (mounted) showTopSnackBar(context, VN.eventUpdated);
      } else {
        final createdEvent = await ref
            .read(eventsProvider.notifier)
            .logEvent(
              summary: summary,
              type: _selectedType,
              tags: _selectedTags.toList(),
              loggedBy: loggedBy,
              orderId: widget.orderId,
            );

        if (hasNewPhotos && mounted) {
          await _uploadPhotos(createdEvent.id, upload);
        }
        if (mounted) showTopSnackBar(context, VN.eventLogged);
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
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
  ) async {
    final service = ref.read(eventServiceProvider);
    await upload.uploadAll(
      _selectedPhotos,
      (file) => service.uploadEventPhoto(eventId, File(file.path)),
    );
    if (mounted && ref.read(photoUploadNotifierProvider).hasErrors) {
      showTopSnackBar(context, VN.eventPhotosUploadFailed);
    }
  }

  Future<void> _changeLogger() async {
    final current = ref.read(loggedByProvider);
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.loggedBy),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: VN.setYourName),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text(VN.save),
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
    final tag = _customTagCtrl.text.trim();
    if (tag.isNotEmpty) {
      setState(() {
        if (!_customTags.contains(tag)) _customTags.add(tag);
        _selectedTags.add(tag);
        _customTagCtrl.clear();
        _showCustomTagField = false;
      });
    } else {
      setState(() => _showCustomTagField = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loggedBy = ref.watch(loggedByProvider);

    final title = _isEditing
        ? VN.editEvent
        : _isOrderLinked
            ? VN.addOrderIncident
            : VN.createEvent;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [AppBarOverflowMenu()],
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
                    '${VN.orderLabel}: ${widget.orderRef}',
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
              labelText: VN.eventSummary,
              hintText: VN.eventPrompt,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(VN.eventType, style: theme.textTheme.titleSmall),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _kTypes.map((t) {
              final selected = _selectedType == t.value;
              return ChoiceChip(
                label: Text(t.label),
                avatar: Icon(t.icon, size: 16),
                selected: selected,
                selectedColor: t.value == 'equipment'
                    ? Colors.orange.shade100
                    : colorScheme.primaryContainer,
                onSelected: (_) => setState(() => _selectedType = t.value),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(VN.tagsLabel, style: theme.textTheme.titleSmall),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              ..._kStandardTags.map(
                (tag) => FilterChip(
                  label: Text(tag.$2),
                  selected: _selectedTags.contains(tag.$1),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _selectedTags.add(tag.$1);
                    } else {
                      _selectedTags.remove(tag.$1);
                    }
                  }),
                ),
              ),
              ..._customTags.map(
                (tag) => FilterChip(
                  label: Text(tag),
                  selected: _selectedTags.contains(tag),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _selectedTags.add(tag);
                    } else {
                      _selectedTags.remove(tag);
                    }
                  }),
                ),
              ),
              if (_showCustomTagField)
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _customTagCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: VN.addTag,
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
                  label: const Text(VN.addTag),
                  onPressed: () => setState(() => _showCustomTagField = true),
                ),
            ],
          ),
          const SizedBox(height: 24),
          EventFormPhotoSection(
            existingPhotos: _existingPhotos,
            selectedPhotos: _selectedPhotos,
            baseUrl: ref.read(apiBaseUrlProvider),
            onSelectionChanged: (files) =>
                setState(() => _selectedPhotos
                  ..clear()
                  ..addAll(files)),
          ),
          UploadProgressIndicator(
            states: ref.watch(photoUploadNotifierProvider).states,
          ),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 18),
              const SizedBox(width: 6),
              Text('${VN.loggedBy}: ', style: theme.textTheme.bodyMedium),
              Text(
                loggedBy.isNotEmpty ? loggedBy : VN.setYourName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: loggedBy.isEmpty ? colorScheme.error : null,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _changeLogger,
                child: const Text(VN.changeLogger),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _isEditing ? VN.save : VN.logEvent,
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
