import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/event.dart';
import '../../providers/events_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/events.dart';

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

/// Full-screen form for creating or editing a bakery event.
///
/// Pass [event] to edit an existing event; omit to create a new one.
class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({super.key, this.event});

  final BakeryEvent? event;

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

  bool get _isEditing => widget.event != null;

  @override
  void initState() {
    super.initState();
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
        if (mounted) {
          showTopSnackBar(context, VN.eventUpdated);
          context.pop();
        }
      } else {
        await ref
            .read(eventsProvider.notifier)
            .logEvent(
              summary: summary,
              type: _selectedType,
              tags: _selectedTags.toList(),
              loggedBy: loggedBy,
            );
        if (mounted) {
          showTopSnackBar(context, VN.eventLogged);
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? VN.editEvent : VN.createEvent),
        actions: const [AppBarOverflowMenu()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary field
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

          // Section: Event type
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

          // Section: Tags (multi-select FilterChip)
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

          // Logged-by row
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

          // Submit button
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
