import 'package:flutter/material.dart';
import 'package:bakery_app/shared/labels/accounting.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
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
    title: const Text(AccountingLabels.accountingLockJournal),
    content: Text(
      '${AccountingLabels.accountingFilterSince} $sinceStr\n'
      '${AccountingLabels.accountingFilterUntil} $untilStr',
    ),
    actions: [
      TextButton(
        onPressed: onCancel,
        child: const Text(SharedLabels.cancel),
      ),
      FilledButton(
        onPressed: onConfirm,
        child: const Text(OrdersLabels.xacNhan),
      ),
    ],
  );
}