import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/work_item.dart';
import '../../../data/providers/blanks_provider.dart';
import '../../../shared/labels/blanks.dart';
import 'add_blank_modal.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// Renders the blank (phôi bánh) section on the CakeDetailScreen (DG-294).
///
/// Shows a "Thêm phôi bánh" button that opens the [showAddBlankModal] and a
/// list of inline blank line items. The add button and the edit/delete actions
/// on line items are available in both read and edit modes (the add modal calls
/// [OrderWorkItemsNotifier.addBlank] which does not require edit mode).
///
/// Mutations are performed through [onAddBlank]/[onUpdateBlank]/[onDeleteBlank]
/// so the widget stays a pure view; the parent wires these callbacks to the
/// `OrderWorkItemsNotifier` blank CRUD methods.
class CakeDetailBlankSection extends ConsumerStatefulWidget {
  const CakeDetailBlankSection({
    super.key,
    required this.orderRef,
    required this.item,
    required this.editing,
    required this.onAddBlank,
    required this.onUpdateBlank,
    required this.onDeleteBlank,
  });

  final String orderRef;
  final WorkItem item;
  final bool editing;

  final Future<BlankAssignment> Function(
    String itemId, {
    required int blankId,
    double quantity,
    String notes,
  }) onAddBlank;

  final Future<BlankAssignment> Function(
    String itemId,
    int blankItemId, {
    double? quantity,
    String? notes,
  }) onUpdateBlank;

  final Future<void> Function(String itemId, int blankItemId) onDeleteBlank;

  @override
  ConsumerState<CakeDetailBlankSection> createState() =>
      _CakeDetailBlankSectionState();
}

class _CakeDetailBlankSectionState
    extends ConsumerState<CakeDetailBlankSection> {
  bool _busy = false;

  Future<void> _withBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAddModal() async {
    final result = await showAddBlankModal(context);
    if (result == null) return;
    await _withBusy(() async {
      await widget.onAddBlank(
        widget.item.id,
        blankId: result.blankId,
        quantity: result.quantity,
        notes: result.notes,
      );
      if (mounted) {
        showTopSnackBar(context, BlanksLabels.messageBlankAdded);
      }
    });
  }

  Future<void> _openEditModal(BlankAssignment assignment) async {
    final result = await showAddBlankModal(
      context,
      initialBlankId: assignment.blankId,
      initialQuantity: assignment.quantity,
      initialNotes: assignment.notes,
      isEdit: true,
    );
    if (result == null) return;
    await _withBusy(() async {
      await widget.onUpdateBlank(
        widget.item.id,
        assignment.id!,
        quantity: result.quantity,
        notes: result.notes,
      );
      if (mounted) {
        showTopSnackBar(context, BlanksLabels.messageBlankUpdated);
      }
    });
  }

  Future<void> _confirmDelete(BlankAssignment assignment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(BlanksLabels.actionDelete),
        content: const Text(BlanksLabels.messageBlankDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(SharedLabels.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(BlanksLabels.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _withBusy(() async {
      await widget.onDeleteBlank(widget.item.id, assignment.id!);
      if (mounted) {
        showTopSnackBar(context, BlanksLabels.messageBlankDeleted);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blanks = widget.item.blanks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel(BlanksLabels.sectionBlanks),
        const SizedBox(height: 8),
          if (blanks.isEmpty)
          Text(
            BlanksLabels.emptyBlanksAssigned,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        for (final assignment in blanks)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _BlankLineItem(
              assignment: assignment,
              blankName: _resolveBlankName(assignment),
              busy: _busy,
              onEdit: () => _openEditModal(assignment),
              onDelete: () => _confirmDelete(assignment),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _openAddModal,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add, size: 18),
          label: const Text(BlanksLabels.actionAddCakeBlank),
        ),
      ],
    );
  }

  /// Resolves a human-readable blank name for [assignment], preferring the
  /// backend-provided `blankName` field and falling back to
  /// [blankByIdProvider] (DG-294 §Technical Approach).
  String _resolveBlankName(BlankAssignment assignment) {
    if (assignment.blankName.isNotEmpty) return assignment.blankName;
    final async = ref.read(blankByIdProvider(assignment.blankId));
    return async.value?.name ?? 'Phôi #${assignment.blankId}';
  }
}

class _BlankLineItem extends StatelessWidget {
  const _BlankLineItem({
    required this.assignment,
    required this.blankName,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final BlankAssignment assignment;
  final String blankName;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  blankName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${BlanksLabels.fieldBlankQuantity}: '
                  '${assignment.quantity.toStringAsFixed(assignment.quantity == assignment.quantity.roundToDouble() ? 0 : 2)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (assignment.notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${BlanksLabels.fieldBlankNotes}: ${assignment.notes}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: BlanksLabels.actionEdit,
            onPressed: busy ? null : onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            tooltip: BlanksLabels.actionDelete,
            onPressed: busy ? null : onDelete,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}