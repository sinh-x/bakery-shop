import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/blank.dart';
import '../../../data/providers/blanks_provider.dart';
import '../../../shared/labels/blanks.dart';
import '../../../shared/utils.dart' show showTopSnackBar;
import 'blank_field_row.dart';
import 'demand_summary_section.dart';
import 'linked_products_section.dart';
import 'stock_summary_section.dart';
import 'blank_form.dart';

/// Body of the blank detail screen (FR1 / AC1).
///
/// Renders the field rows, stock/demand/linked-products summary sections, and
/// the edit / audit / delete action buttons. Hosts the delete confirmation
/// dialog. Extracted from `blank_detail_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class BlankDetailBody extends ConsumerWidget {
  const BlankDetailBody({super.key, required this.blankId, required this.blank});

  final int blankId;
  final Blank blank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        BlankFieldRow(label: BlanksLabels.fieldName, value: blank.name),
        BlankFieldRow(label: BlanksLabels.fieldCategory, value: blank.category),
        BlankFieldRow(label: BlanksLabels.fieldUnit, value: blank.unit),
        BlankFieldRow(label: BlanksLabels.fieldNote, value: blank.notes),
        const SizedBox(height: 24),
        StockSummarySection(blankId: blankId),
        const SizedBox(height: 16),
        DemandSummarySection(blankId: blankId),
        const SizedBox(height: 24),
        LinkedProductsSection(blankId: blankId),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => showBlankForm(context, blank: blank),
          icon: const Icon(Icons.edit),
          label: const Text(BlanksLabels.actionEdit),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => context.push('/blanks/$blankId/audit-log'),
          icon: const Icon(Icons.history),
          label: const Text(BlanksLabels.screenHistory),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => _confirmDelete(context, ref),
          icon: const Icon(Icons.delete_outline),
          label: const Text(BlanksLabels.actionDelete),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: const Text(BlanksLabels.messageDeleteConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(BlanksLabels.actionCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(BlanksLabels.actionDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ref.read(blanksProvider.notifier).deleteBlank(blankId);
      if (context.mounted) {
        showTopSnackBar(context, BlanksLabels.messageDeleteSuccess);
        context.pop();
      }
    } catch (e) {
      if (context.mounted) {
        showTopSnackBar(context, BlanksLabels.messageDeleteBlocked);
      }
    }
  }
}