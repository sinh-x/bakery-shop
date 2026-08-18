// EXEMPT: 200-line threshold exceeded because the transaction detail sheet
// renders payment, deposit, and refund sections with per-row formatting that
// does not split cleanly into independent widgets without duplicating state.
// Reviewed 2026-07-30.
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart' show formatVND, paymentMethodLabel, showTopSnackBar, txnTypeLabel;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/payment_transaction.dart';
import '../../../../providers/order_providers.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'order_detail_helpers.dart';
import 'order_detail_row.dart';
import 'txn_photo_section.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// Bottom sheet showing a single payment transaction's details with
/// invalidate / restore / edit actions.
class OrderTransactionDetailSheet extends ConsumerStatefulWidget {
  const OrderTransactionDetailSheet({
    super.key,
    required this.txn,
    required this.orderRef,
    required this.onEdit,
  });

  final PaymentTransaction txn;
  final String orderRef;
  final VoidCallback onEdit;

  @override
  ConsumerState<OrderTransactionDetailSheet> createState() =>
      _OrderTransactionDetailSheetState();
}

class _OrderTransactionDetailSheetState
    extends ConsumerState<OrderTransactionDetailSheet> {
  bool _acting = false;

  PaymentTransaction get txn => widget.txn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = txnColor(txn.type);
    final typeLabel = txnTypeLabel(txn.type);
    final methodLabel = paymentMethodLabel(txn.method);
    final isInvalidated = txn.invalidatedAt != null;

    String dateStr = '';
    if (txn.createdAt != null) {
      dateStr = formatDisplay(txn.createdAt);
    }

    String invalidatedDateStr = '';
    if (txn.invalidatedAt != null) {
      invalidatedDateStr = formatDisplay(txn.invalidatedAt);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isInvalidated
                      ? theme.colorScheme.outline.withAlpha(20)
                      : color.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isInvalidated
                        ? theme.colorScheme.outline.withAlpha(100)
                        : color.withAlpha(100),
                  ),
                ),
                child: Text(
                  isInvalidated ? OrdersLabels.txnInvalidatedBadge : typeLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isInvalidated ? theme.colorScheme.outline : color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                txn.type == 'refund'
                    ? '-${formatVND(txn.amount)}'
                    : formatVND(txn.amount),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isInvalidated
                      ? theme.colorScheme.outline
                      : (txn.type == 'refund' ? Colors.orange : Colors.green),
                  decoration:
                      isInvalidated ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          OrderDetailRow(label: OrdersLabels.paymentMethod, value: methodLabel),
          if (txn.paymentSource != null && txn.paymentSource!.isNotEmpty)
            OrderDetailRow(
              label: ExpensesLabels.paymentTargetAccountLabel,
              value: txn.paymentSource!,
            ),
          if (dateStr.isNotEmpty) OrderDetailRow(label: OrdersLabels.txnType, value: dateStr),
          if (txn.notes.isNotEmpty)
            OrderDetailRow(label: OrdersLabels.txnNoteLabel, value: txn.notes),
          if (isInvalidated) ...[
            const SizedBox(height: 8),
            if (invalidatedDateStr.isNotEmpty)
              OrderDetailRow(
                label: OrdersLabels.txnInvalidatedAtLabel,
                value: invalidatedDateStr,
              ),
            if (txn.invalidatedBy.isNotEmpty)
              OrderDetailRow(
                label: OrdersLabels.txnInvalidatedByLabel,
                value: txn.invalidatedBy,
              ),
          ],
          const SizedBox(height: 20),
          TxnPhotoSection(
            orderRef: widget.orderRef,
            txnId: txn.id,
            showRemove: false,
            showEmptyState: true,
          ),
          const SizedBox(height: 20),
          if (_acting)
            const Center(child: CircularProgressIndicator())
          else ...[
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onEdit();
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text(OrdersLabels.editPayment),
            ),
            const SizedBox(height: 8),
            if (isInvalidated)
              FilledButton.icon(
                onPressed: _onRestore,
                icon: const Icon(Icons.restore, size: 18),
                label: const Text(OrdersLabels.restorePayment),
              )
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                ),
                onPressed: _onInvalidate,
                icon: const Icon(Icons.block_outlined, size: 18),
                label: const Text(OrdersLabels.invalidatePayment),
              ),
          ],
        ],
      ),
    );
  }

  // ── Per-transaction photo (DG-410 Phase 4 / CQ-1) ─────────────────────────
  //
  // The detail sheet's photo section is now rendered by the shared
  // [TxnPhotoSection] widget (see txn_photo_section.dart), which centralizes
  // the pick / remove / busy-state logic that previously lived as
  // duplicated `_pickTxnPhoto` / `_buildTxnPhotoSection` copies here and in
  // the edit sheet.

  Future<void> _onInvalidate() async {
    final reason = await _showInvalidateReasonDialog();
    if (reason == null || !mounted) return;
    setState(() => _acting = true);
    try {
      await ref
          .read(orderPaymentTransactionsProvider(widget.orderRef).notifier)
          .invalidate(txn.id, reason: reason);
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, OrdersLabels.paymentInvalidated);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _onRestore() async {
    final confirmed = await _showRestoreConfirmDialog();
    if (!confirmed || !mounted) return;
    setState(() => _acting = true);
    try {
      await ref
          .read(orderPaymentTransactionsProvider(widget.orderRef).notifier)
          .restore(txn.id);
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, OrdersLabels.paymentRestored);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<String?> _showInvalidateReasonDialog() async {
    final ctrl = TextEditingController();
    final theme = Theme.of(context);
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text(OrdersLabels.invalidateConfirmTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(OrdersLabels.invalidateConfirmMessage),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: OrdersLabels.invalidateReasonLabel,
                    hintText: OrdersLabels.invalidateReasonHint,
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  autofocus: true,
                  onChanged: (_) => setS(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(SharedLabels.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                ),
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text(OrdersLabels.invalidatePayment),
              ),
            ],
          ),
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<bool> _showRestoreConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(OrdersLabels.restoreConfirmTitle),
        content: const Text(OrdersLabels.restoreConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(SharedLabels.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(OrdersLabels.restorePayment),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}