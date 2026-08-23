import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart'
    show ImagePicker, ImageSource, XFile;

import '../../../../data/api/order_service.dart';
import '../../../../providers/order_providers.dart';
import '../../providers/order_record_payment_notifier.dart';
import '../../providers/order_draft_contexts.dart';
import '../../providers/order_form_operation_notifier.dart';
import '../../../../shared/models/form_draft_context.dart';
import '../../../pos/widgets/pos_checkout_dialogs.dart';
import 'package:bakery_app/shared/utils/vnd_units.dart';
import 'package:bakery_app/shared/widgets/target_account_dropdown.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/widgets/discard_form_draft_action.dart';
import 'txn_date_time_picker_row.dart';
import '../../../../providers/form_draft_session_notifier.dart';

/// Sanitizes an account name for use as a photo tag: spaces → hyphens,
/// special chars stripped (FR4). E.g. `TK Phượng VCB` → `TK-Phượng-VCB`.
/// Unicode letters/digits are preserved; only ASCII punctuation/symbols
/// (other than hyphen) are stripped.
@visibleForTesting
String sanitizeAccountTag(String? account) {
  if (account == null || account.isEmpty) return '';
  var sanitized = account.replaceAll(' ', '-');
  // Strip any character that is not a Unicode letter, digit, or hyphen.
  sanitized = sanitized.replaceAll(
    RegExp(r'[^\p{L}\p{N}-]', unicode: true),
    '',
  );
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
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  late final OrderRecordPaymentNotifier _draftNotifier;
  late final FormDraftContext _draftContext;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _draftContext = OrderDraftContexts.recordPayment(widget.orderRef);
    _draftNotifier = ref.read(
      orderRecordPaymentDraftProvider(_draftContext).notifier,
    );
    final draft = ref.read(orderRecordPaymentDraftProvider(_draftContext));
    _amountCtrl = TextEditingController(text: draft.amount)
      ..addListener(_persistAmount);
    _notesCtrl = TextEditingController(text: draft.notes)
      ..addListener(_persistNotes);
  }

  void _persistAmount() => _draftNotifier.setAmount(_amountCtrl.text);

  void _persistNotes() => _draftNotifier.setNotes(_notesCtrl.text);

  void _onTypeSelected(String type) {
    _draftNotifier.setType(type);
    if (type == 'full_payment' && widget.remaining > 0) {
      // Display the amount in thousands (user types 200 → means 200,000)
      _amountCtrl.text = vndThousandsTextFromAmount(widget.remaining);
    }
  }

  void _onMethodSelected(String method) {
    _draftNotifier.setMethod(method);
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
    _draftNotifier.setPendingTransferPhoto(image);
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_persistAmount);
    _notesCtrl.removeListener(_persistNotes);
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final draftProvider = orderRecordPaymentDraftProvider(_draftContext);
    final draft = container.read(draftProvider);
    final expectedDraft = container.read(
      formDraftSessionProvider,
    )[_draftContext];
    final operation = container.read(
      orderFormOperationProvider(_draftContext).notifier,
    );
    final generation = operation.start();
    final transactions = container.read(
      orderPaymentTransactionsProvider(widget.orderRef).notifier,
    );
    final orderService = container.read(orderServiceProvider);
    final notes = _notesCtrl.text.trim();
    final amount = vndFromThousands(double.parse(_amountCtrl.text.trim()));
    XFile? uploadedPendingPhoto;
    try {
      final txn = await transactions.record(
        amount: amount,
        type: draft.type,
        method: draft.method,
        notes: notes,
        paymentSource: draft.paymentSource,
        createdAt: draft.createdAt,
      );
      // Upload the transfer proof photo after the payment is recorded (FR3).
      // Tags = 'chuyen-khoan,<sanitized-account>' (FR3/FR4). The photo upload
      // is best-effort: a failure does not roll back the recorded payment.
      final pendingPhoto = draft.pendingTransferPhoto;
      if (draft.method == 'transfer' && pendingPhoto != null) {
        final accountTag = sanitizeAccountTag(draft.paymentSource);
        final tags = accountTag.isEmpty
            ? 'chuyen-khoan'
            : 'chuyen-khoan,$accountTag';
        try {
          final photo = await orderService.uploadOrderPhoto(
            widget.orderRef,
            pendingPhoto,
            tags: tags,
          );
          uploadedPendingPhoto = pendingPhoto;
          container.invalidate(orderPhotosProvider(widget.orderRef));
          // Link the just-uploaded order-level photo to the new transaction
          // via the join table (FR2 / AC1). Best-effort: a link failure does
          // not roll back the recorded payment or the order-level upload.
          try {
            await transactions.linkPhoto(txn.id, photo.photoHash);
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
      }
      if (operation.isCurrent(generation)) {
        final cleared =
            expectedDraft != null &&
            container
                .read(formDraftSessionProvider.notifier)
                .clearDraftIfUnchanged(_draftContext, expectedDraft);
        if (!cleared && uploadedPendingPhoto != null) {
          container
              .read(draftProvider.notifier)
              .removeUploadedPendingPhoto(uploadedPendingPhoto);
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
      operation.failIfCurrent(generation, e);
      if (mounted) {
        showTopSnackBar(context, '${SharedLabels.apiError}: $e');
      }
    } finally {
      operation.finishIfCurrent(generation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ref.watch(orderRecordPaymentDraftProvider(_draftContext));
    final operation = ref.watch(orderFormOperationProvider(_draftContext));

    const types = [
      ('deposit', OrdersLabels.txnTypeDeposit),
      ('payment', OrdersLabels.txnTypePayment),
      ('full_payment', OrdersLabels.txnTypeFullPayment),
      ('tien_rut', OrdersLabels.txnTypeRutTien),
      ('refund', OrdersLabels.txnTypeRefund),
    ];
    const methods = [
      ('cash', OrdersLabels.methodCash),
      ('transfer', OrdersLabels.methodTransfer),
    ];

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
            Text(
              OrdersLabels.paymentMethod,
              style: theme.textTheme.labelMedium,
            ),
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
                if (v == null || v.trim().isEmpty) {
                  return SharedLabels.fieldRequired;
                }
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) {
                  return SharedLabels.invalidPrice;
                }
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
                  .read(orderRecordPaymentDraftProvider(_draftContext).notifier)
                  .setCreatedDate,
              onTimeChanged: ref
                  .read(orderRecordPaymentDraftProvider(_draftContext).notifier)
                  .setCreatedTime,
            ),
            if (s.method == 'transfer') ...[
              const SizedBox(height: 12),
              TargetAccountDropdown(
                value: s.paymentSource,
                onChanged: (value) => ref
                    .read(
                      orderRecordPaymentDraftProvider(_draftContext).notifier,
                    )
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
            DiscardFormDraftAction(
              isDirty: s.isDirty,
              onDiscard: () {
                _draftNotifier.clearDraft();
                Navigator.pop(context);
              },
            ),
            FilledButton(
              onPressed: operation.busy ? null : _submit,
              child: operation.busy
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
