import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import 'package:bakery_app/shared/labels/orders.dart';

/// Edit-specific due-date-change decision dialog for orders with a public
/// order code. Shown before save when the due date changed and the order has
/// a non-empty public code (preserves the edit-specific public-code dialog).
Future<String?> showPublicCodeDateChangeDecision(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(VN.publicCodeDateChangeTitle),
      content: const Text(VN.publicCodeDateChangePrompt),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text(VN.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop('keep'),
          child: const Text(VN.publicCodeKeep),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop('regenerate'),
          child: const Text(VN.publicCodeRegenerate),
        ),
      ],
    ),
  );
}

/// Determines whether the public-code date-change decision dialog should be
/// shown before save: only when the due date changed and the order has a
/// non-empty public order code.
bool shouldAskPublicCodeDateDecision(Order? originalOrder, String? newDueDate) {
  if (originalOrder == null) return false;
  if (newDueDate == originalOrder.dueDate) return false;
  return originalOrder.publicOrderCode.trim().isNotEmpty;
}