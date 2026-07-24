import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/blank.dart';
import '../../data/providers/blanks_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'widgets/blank_form.dart';

/// View / edit / delete a single blank (FR1 / AC1).
///
/// Route: `/blanks/:id`. Displays all blank fields, with actions to edit
/// (opens [BlankForm] in edit mode), delete (with confirmation dialog), and
/// placeholder buttons for BOM mapping (Phase 4.5) and audit log (Phase 4.8).
class BlankDetailScreen extends ConsumerWidget {
  const BlankDetailScreen({super.key, required this.blankId});

  final int blankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blankAsync = ref.watch(blankByIdProvider(blankId));
    return Scaffold(
      appBar: AppBar(
        title: const Text(BlanksLabels.screenDetail),
        actions: const [AppBarOverflowMenu()],
      ),
      body: blankAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _DetailErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(blankByIdProvider(blankId)),
        ),
        data: (blank) => _BlankDetailBody(blankId: blank.id, blank: blank),
      ),
    );
  }
}

class _BlankDetailBody extends ConsumerWidget {
  const _BlankDetailBody({required this.blankId, required this.blank});

  final int blankId;
  final Blank blank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _BlankFieldRow(label: BlanksLabels.fieldName, value: blank.name),
        _BlankFieldRow(label: BlanksLabels.fieldCategory, value: blank.category),
        _BlankFieldRow(label: BlanksLabels.fieldUnit, value: blank.unit),
        _BlankFieldRow(label: BlanksLabels.fieldNote, value: blank.notes),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => showBlankForm(context, blank: blank),
          icon: const Icon(Icons.edit),
          label: const Text(BlanksLabels.actionEdit),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => context.push('/blanks/$blankId/bom'),
          icon: const Icon(Icons.link),
          label: const Text(BlanksLabels.screenBomMapping),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => context.push('/blanks/$blankId/history'),
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

class _BlankFieldRow extends StatelessWidget {
  const _BlankFieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}

class _DetailErrorView extends StatelessWidget {
  const _DetailErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(VN.apiError, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text(VN.retry),
          ),
        ],
      ),
    );
  }
}