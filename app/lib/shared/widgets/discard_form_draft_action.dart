import 'dart:async';

import 'package:flutter/material.dart';

import '../labels/shared.dart';

/// A shared clear-draft action that is absent until the draft is dirty.
class DiscardFormDraftAction extends StatelessWidget {
  const DiscardFormDraftAction({
    required this.isDirty,
    required this.onDiscard,
    super.key,
  });

  final bool isDirty;
  final FutureOr<void> Function() onDiscard;

  @override
  Widget build(BuildContext context) {
    if (!isDirty) return const SizedBox.shrink();

    return TextButton.icon(
      onPressed: () => _confirmDiscard(context),
      icon: const Icon(Icons.delete_sweep_outlined),
      label: const Text(SharedLabels.clearDraft),
    );
  }

  Future<void> _confirmDiscard(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(SharedLabels.clearDraftConfirmationTitle),
        content: const Text(SharedLabels.clearDraftConfirmationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(SharedLabels.keepDraft),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(SharedLabels.clearDraft),
          ),
        ],
      ),
    );
    if (confirmed == true) await onDiscard();
  }
}
