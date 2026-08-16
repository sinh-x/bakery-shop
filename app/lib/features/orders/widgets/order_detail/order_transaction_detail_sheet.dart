// EXEMPT: 200-line threshold exceeded because the transaction detail sheet
// renders payment, deposit, and refund sections with per-row formatting that
// does not split cleanly into independent widgets without duplicating state.
// Reviewed 2026-07-30.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart'
    show ImagePicker, ImageSource, XFile;

import '../../../../data/api/api_client.dart' show apiBaseUrlProvider;
import '../../../../data/models/order_photo.dart';
import '../../../../data/models/payment_transaction.dart';
import '../../../../providers/order_providers.dart';
import '../../../pos/widgets/pos_checkout_dialogs.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'order_detail_helpers.dart';
import 'order_detail_row.dart';
import 'order_photo_thumbnail.dart';
import '../order_photo_section.dart';

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
  bool _photoBusy = false;

  PaymentTransaction get txn => widget.txn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseUrl = ref.watch(apiBaseUrlProvider);
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
                  isInvalidated ? VN.txnInvalidatedBadge : typeLabel,
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
          OrderDetailRow(label: VN.paymentMethod, value: methodLabel),
          if (txn.paymentSource != null && txn.paymentSource!.isNotEmpty)
            OrderDetailRow(
              label: VN.paymentTargetAccountLabel,
              value: txn.paymentSource!,
            ),
          if (dateStr.isNotEmpty) OrderDetailRow(label: VN.txnType, value: dateStr),
          if (txn.notes.isNotEmpty)
            OrderDetailRow(label: VN.txnNoteLabel, value: txn.notes),
          if (isInvalidated) ...[
            const SizedBox(height: 8),
            if (invalidatedDateStr.isNotEmpty)
              OrderDetailRow(
                label: VN.txnInvalidatedAtLabel,
                value: invalidatedDateStr,
              ),
            if (txn.invalidatedBy.isNotEmpty)
              OrderDetailRow(
                label: VN.txnInvalidatedByLabel,
                value: txn.invalidatedBy,
              ),
          ],
          const SizedBox(height: 20),
          _buildTxnPhotoSection(theme, baseUrl),
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
              label: const Text(VN.editPayment),
            ),
            const SizedBox(height: 8),
            if (isInvalidated)
              FilledButton.icon(
                onPressed: _onRestore,
                icon: const Icon(Icons.restore, size: 18),
                label: const Text(VN.restorePayment),
              )
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error),
                ),
                onPressed: _onInvalidate,
                icon: const Icon(Icons.block_outlined, size: 18),
                label: const Text(VN.invalidatePayment),
              ),
          ],
        ],
      ),
    );
  }

  // ── Per-transaction photo (DG-410 Phase 4) ─────────────────────────────
  //
  // The detail sheet lazily fetches the transaction's attached photo via
  // [transactionPhotoProvider] (NFR3 — no extra fetch on tab switch) and
  // shows it as a thumbnail (tap to enlarge). Inline add/replace uses the
  // same `showTransferSourceDialog` + `ImagePicker` pattern as the record
  // and edit sheets (FR4 / AC3).

  Future<void> _pickTxnPhoto() async {
    FocusScope.of(context).unfocus();
    final source = await showTransferSourceDialog(context);
    if (source == null || source == 'skip' || !mounted) return;
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source as ImageSource,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      await ref
          .read(orderPaymentTransactionsProvider(widget.orderRef).notifier)
          .attachPhoto(txn.id, image);
      if (mounted) {
        showTopSnackBar(context, VN.txnPhotoSaved);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.txnPhotoSaveFailed}: $e');
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Widget _buildTxnPhotoSection(ThemeData theme, String baseUrl) {
    final photoAsync =
        ref.watch(transactionPhotoProvider((widget.orderRef, txn.id)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(VN.txnPhotoSection, style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        photoAsync.when(
          loading: () => const SizedBox(
            height: 90,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text(
            '${VN.txnPhotoSaveFailed}: $e',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
          data: (photo) {
            if (photo == null || photo.photoHash == null) {
              // No photo attached — empty state + inline attach (AC3).
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      VN.txnPhotoEmpty,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: VN.txnPhotoAttach,
                    child: TextButton.icon(
                      onPressed: _photoBusy ? null : _pickTxnPhoto,
                      icon: const Icon(Icons.photo_camera_outlined, size: 20),
                      label: const Text(VN.txnPhotoAttach),
                    ),
                  ),
                ],
              );
            }
            final url = '$baseUrl/api/photos/${photo.photoHash}.jpg';
            // Synthesize an [OrderPhoto] so the shared [OrderPhotoViewer]
            // (which only reads photoHash + tags) can display the single
            // transaction photo full-screen (FR4 reuse / tap to enlarge).
            final viewerPhoto = OrderPhoto(
              id: int.tryParse(photo.id) ?? 0,
              orderId: 0,
              photoHash: photo.photoHash!,
              tags: 'chuyen-khoan',
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: VN.txnPhotoTapToEnlarge,
                  child: OrderPhotoThumbnail(
                    url: url,
                    tags: 'chuyen-khoan',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OrderPhotoViewer(
                          photos: [viewerPhoto],
                          initialIndex: 0,
                          baseUrl: baseUrl,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Tooltip(
                      message: VN.txnPhotoReplace,
                      child: TextButton.icon(
                        onPressed: _photoBusy ? null : _pickTxnPhoto,
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label: const Text(VN.txnPhotoReplace),
                      ),
                    ),
                  ),
                ),
                if (_photoBusy)
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 32),
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

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
        showTopSnackBar(context, VN.paymentInvalidated);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
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
        showTopSnackBar(context, VN.paymentRestored);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
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
            title: const Text(VN.invalidateConfirmTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(VN.invalidateConfirmMessage),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: VN.invalidateReasonLabel,
                    hintText: VN.invalidateReasonHint,
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
                child: const Text(VN.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                ),
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text(VN.invalidatePayment),
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
        title: const Text(VN.restoreConfirmTitle),
        content: const Text(VN.restoreConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(VN.restorePayment),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}