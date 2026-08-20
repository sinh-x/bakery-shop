import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource, XFile;

import '../../../../data/api/order_service.dart';
import '../../../../providers/order_providers.dart';
import '../../providers/order_record_payment_notifier.dart';
import '../../../pos/widgets/pos_checkout_dialogs.dart';
import 'package:bakery_app/shared/utils/vnd_units.dart';
import 'package:bakery_app/shared/widgets/target_account_dropdown.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'txn_date_time_picker_row.dart';
/// Sanitizes an account name for use as a photo tag: spaces → hyphens,
/// special chars stripped (FR4). E.g. `TK Phượng VCB` → `TK-Phượng-VCB`.
/// Unicode letters/digits are preserved; only ASCII punctuation/symbols
/// (other than hyphen) are stripped.
@visibleForTesting
String sanitizeAccountTag(String? account) {
  if (account == null || account.isEmpty) return '';
  var sanitized = account.replaceAll(' ', '-');
  // Strip any character that is not a Unicode letter, digit, or hyphen.
  sanitized = sanitized.replaceAll(RegExp(r'[^\p{L}\p{N}-]', unicode: true), '');
  // Collapse repeated hyphens and trim leading/trailing hyphens.
  sanitized = sanitized.replaceAll(RegExp(r'-+'), '-');
  if (sanitized.startsWith('-')) sanitized = sanitized.substring(1);
  if (sanitized.endsWith('-')) {
    sanitized = sanitized.substring(0, sanitized.length - 1);
  }
  return sanitized;
}

/// Bottom sheet for recording a new payment transaction against an order.
class OrderRecordPaymentSheet extends ConsumerStatefulWidget {
  const OrderRecordPaymentSheet({
    super.key,
    required this.orderRef,
    required this.remaining,
  });

  final String orderRef;
  final double remaining;

  @override
  ConsumerState<OrderRecordPaymentSheet> createState() =>
      _OrderRecordPaymentSheetState();
}

class _OrderRecordPaymentSheetState
    extends ConsumerState<OrderRecordPaymentSheet> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
  }

  void _onTypeSelected(String type) {
    ref.read(orderRecordPaymentProvider.notifier).setType(type);
    if (type == 'full_payment' && widget.remaining > 0) {
      // Display the amount in thousands (user types 200 → means 200,000)
      _amountCtrl.text = vndThousandsTextFromAmount(widget.remaining);
    }
  }

  void _onMethodSelected(String method) {
    ref.read(orderRecordPaymentProvider.notifier).setMethod(method);
  }

  /// Opens the camera/gallery picker (FR2) reusing the POS checkout
  /// `showTransferSourceDialog` pattern. The keyboard is dismissed before
  /// showing the picker so the bottom sheet does not overflow when the
  /// keyboard is visible (NFR2).
  Future<void> _pickTransferPhoto() async {
    FocusScope.of(context).unfocus();
    final source = await showTransferSourceDialog(context);
    if (source == null || source == 'skip' || !mounted) return;
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source as ImageSource,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    ref.read(orderRecordPaymentProvider.notifier).setPendingTransferPhoto(image);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Multiply by 1000: staff types 200 → actual amount 200,000
    final amount = vndFromThousands(double.parse(_amountCtrl.text.trim()));
    ref.read(orderRecordPaymentProvider.notifier).setSubmitting(true);
    try {
      final s = ref.read(orderRecordPaymentProvider);
      // Capture the created txn so its id can link the uploaded photo (FR2).
      final txn = await ref
          .read(orderPaymentTransactionsProvider(widget.orderRef).notifier)
          .record(
            amount: amount,
            type: s.type,
            method: s.method,
            notes: _notesCtrl.text.trim(),
            paymentSource: s.paymentSource,
            createdAt: s.createdAt,
          );
      // Upload the transfer proof photo after the payment is recorded (FR3).
      // Tags = 'chuyen-khoan,<sanitized-account>' (FR3/FR4). The photo upload
      // is best-effort: a failure does not roll back the recorded payment.
      final pendingPhoto = s.pendingTransferPhoto;
      if (s.method == 'transfer' && pendingPhoto != null) {
        final accountTag = sanitizeAccountTag(s.paymentSource);
        final tags = accountTag.isEmpty
            ? 'chuyen-khoan'
            : 'chuyen-khoan,$accountTag';
        try {
          final photo = await ref.read(orderServiceProvider).uploadOrderPhoto(
                widget.orderRef,
                pendingPhoto,
                tags: tags,
              );
          ref.invalidate(orderPhotosProvider(widget.orderRef));
          // Link the just-uploaded order-level photo to the new transaction
          // via the join table (FR2 / AC1). Best-effort: a link failure does
          // not roll back the recorded payment or the order-level upload.
          try {
            await ref
                .read(orderPaymentTransactionsProvider(widget.orderRef)
                    .notifier)
                .linkPhoto(txn.id, photo.photoHash);
            if (mounted) {
              showTopSnackBar(context, OrdersLabels.txnPhotoLinked);
            }
          } catch (e) {
            if (mounted) {
              showTopSnackBar(context, OrdersLabels.txnPhotoLinkFailed);
            }
          }
          if (mounted) {
            showTopSnackBar(context, OrdersLabels.transferPhotoUploaded);
          }
        } catch (e) {
          if (mounted) {
            showTopSnackBar(context, OrdersLabels.transferPhotoUploadFailed);
          }
        }
        // Clear the pending photo after the upload attempt (both success and
        // failure) so the field does not outlive its purpose and the
        // payment-recorded snackbar suppression logic below stays consistent
        // (DG-364 review-auto cycle 1, MN-3).
        if (mounted) {
          ref.read(orderRecordPaymentProvider.notifier).clearPendingTransferPhoto();
        }
      }
      if (mounted) {
        Navigator.pop(context);
        // The payment-recorded snackbar is always shown when a payment was
        // persisted. The transfer photo outcome snackbar (success or failure)
        // is shown separately above so the user knows both the payment result
        // and the photo upload result (MN-1, MN-5).
        showTopSnackBar(context, OrdersLabels.paymentRecorded);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    } finally {
      if (mounted) ref.read(orderRecordPaymentProvider.notifier).setSubmitting(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ref.watch(orderRecordPaymentProvider);

    const types = [
      ('deposit', OrdersLabels.txnTypeDeposit),
      ('payment', OrdersLabels.txnTypePayment),
      ('full_payment', OrdersLabels.txnTypeFullPayment),
      ('tien_rut', OrdersLabels.txnTypeRutTien),
      ('refund', OrdersLabels.txnTypeRefund),
    ];
    const methods = [('cash', OrdersLabels.methodCash), ('transfer', OrdersLabels.methodTransfer)];

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(OrdersLabels.addPayment, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Text(OrdersLabels.txnType, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: types
                  .map(
                    (t) => ChoiceChip(
                      label: Text(t.$2),
                      selected: s.type == t.$1,
                      onSelected: (_) => _onTypeSelected(t.$1),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(OrdersLabels.paymentMethod, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: methods
                  .map(
                    (m) => ChoiceChip(
                      label: Text(m.$2),
                      selected: s.method == m.$1,
                      onSelected: (_) => _onMethodSelected(m.$1),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: OrdersLabels.paymentAmountLabel,
                border: OutlineInputBorder(),
                suffixText: ',000đ',
                helperText: OrdersLabels.paymentThousandsHint,
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return SharedLabels.fieldRequired;
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return SharedLabels.invalidPrice;
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: OrdersLabels.paymentNotes,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // DG-415 Phase 3 / FR1, FR7 — date+time picker defaults to now
            // and is limited to past→today. The notifier merges date+time so
            // the picked timestamp persists as UTC Z on save (AC2).
            TxnDateTimePickerRow(
              dateTime: s.createdAt ?? DateTime.now(),
              onDateChanged: ref
                  .read(orderRecordPaymentProvider.notifier)
                  .setCreatedDate,
              onTimeChanged: ref
                  .read(orderRecordPaymentProvider.notifier)
                  .setCreatedTime,
            ),
            if (s.method == 'transfer') ...[
              const SizedBox(height: 12),
              TargetAccountDropdown(
                value: s.paymentSource,
                onChanged: (value) => ref
                    .read(orderRecordPaymentProvider.notifier)
                    .setPaymentSource(value),
              ),
              const SizedBox(height: 8),
              // Photo attachment button (FR2): reuses the
              // `showTransferSourceDialog` pattern from POS checkout. The
              // selected photo is uploaded after the payment is recorded
              // (FR3) with tags 'chuyen-khoan,<sanitized-account>' (FR4).
              Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: OrdersLabels.attachTransferPhotoTooltip,
                  child: TextButton.icon(
                    onPressed: _pickTransferPhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 20),
                    label: Text(
                      s.pendingTransferPhoto == null
                          ? OrdersLabels.attachTransferPhoto
                          : OrdersLabels.transferPhotoSelected,
                    ),
                  ),
                ),
              ),
              if (s.pendingTransferPhoto != null) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text(
                    s.pendingTransferPhoto!.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: s.submitting ? null : _submit,
              child: s.submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(OrdersLabels.addPayment),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}