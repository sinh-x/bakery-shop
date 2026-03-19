import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/events_provider.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

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

  String _selectedType = 'note';
  final _selectedTags = <String>{};
  final _customTags = <String>[];
  bool _showCustomTagField = false;
  bool _saving = false;

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

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final loggedBy = ref.read(loggedByProvider);
      await ref.read(eventsProvider.notifier).logEvent(
            summary: summary,
            type: _selectedType,
            tags: _selectedTags.toList(),
            loggedBy: loggedBy,
          );
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text(VN.eventLogged)),
        );
        _reset();
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    _summaryCtrl.clear();
    setState(() {
      _selectedType = 'note';
      _selectedTags.clear();
      _customTags.clear();
      _showCustomTagField = false;
    });
    _summaryFocus.requestFocus();
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
            hintText: VN.eventPrompt,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),

        // Type chips — single-select, equipment highlighted orange
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
        const SizedBox(height: 8),

        // Tag chips — multi-select + inline custom tag
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
        const SizedBox(height: 12),

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
        const SizedBox(height: 16),

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
              : const Text(
                  VN.logEvent,
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
