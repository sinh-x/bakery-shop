import 'package:flutter/material.dart';

import '../../../shared/widgets/vietnamese_labels.dart';

/// Builds the confirmation [AlertDialog] for the journal lock action.
///
/// Extracted from journal_tab.dart (DG-189 Phase 1, finding M-2) to keep
/// journal_tab.dart within the Flutter coding-standards size budget.
AlertDialog buildLockConfirmDialog({
  required String sinceStr,
  required String untilStr,
  required void Function() onCancel,
  required void Function() onConfirm,
}) {
  return AlertDialog(
    title: const Text(VN.accountingLockJournal),
    content: Text(
      '${VN.accountingFilterSince} $sinceStr\n'
      '${VN.accountingFilterUntil} $untilStr',
    ),
    actions: [
      TextButton(
        onPressed: onCancel,
        child: const Text(VN.cancel),
      ),
      FilledButton(
        onPressed: onConfirm,
        child: const Text(VN.xacNhan),
      ),
    ],
  );
}