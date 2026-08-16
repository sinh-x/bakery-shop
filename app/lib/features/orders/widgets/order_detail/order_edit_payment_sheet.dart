import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart'
    show ImagePicker, ImageSource, XFile;

import '../../../../data/api/api_client.dart' show apiBaseUrlProvider;
import '../../../../data/models/order_photo.dart';
import '../../../../data/models/payment_transaction.dart';
import '../../../../providers/order_providers.dart';
import '../../../pos/widgets/pos_checkout_dialogs.dart';
import 'package:bakery_app/shared/utils/vnd_units.dart';
import 'package:bakery_app/shared/widgets/target_account_dropdown.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'order_photo_thumbnail.dart';
import '../order_photo_section.dart';

/// Bottom sheet for editing an existing payment transaction.
class OrderEditPaymentSheet extends ConsumerStatefulWidget {
  const OrderEditPaymentSheet({
    super.key,
    required this.orderRef,
    required this.txn,
  });

  final String orderRef;
  final PaymentTransaction txn;

  @override
  ConsumerState<OrderEditPaymentSheet> createState() =>
      _OrderEditPaymentSheetState();
}

class _OrderEditPaymentSheetState
    extends ConsumerState<OrderEditPaymentSheet> {
  late String _type;
  late String _method;
  String? _paymentSource;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    _type = widget.txn.type;
    _method = widget.txn.method;
    _paymentSource = widget.txn.paymentSource;
    // Convert back from actual amount to thousands for display
    _amountCtrl = TextEditingController(
      text: vndThousandsTextFromAmount(widget.txn.amount),
    );
    _notesCtrl = TextEditingController(text: widget.txn.notes);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = vndFromThousands(double.parse(_amountCtrl.text.trim()));
    setState(() => _submitting = true);
    try {
      await ref
          .read(orderPaymentTransactionsProvider(widget.orderRef).notifier)
          .edit(
            widget.txn.id,
            amount: amount,
            type: _type,
            method: _method,
            notes: _notesCtrl.text.trim(),
            paymentSource: _paymentSource,
          );
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, VN.paymentUpdated);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.apiError}: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Opens the camera/gallery picker (FR3 add/replace). Reuses the POS
  /// `showTransferSourceDialog` pattern. The keyboard is dismissed before
  /// showing the picker so the bottom sheet does not overflow.
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
          .attachPhoto(widget.txn.id, image);
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

  /// Removes the transaction's attached photo (FR3 remove).
  Future<void> _removeTxnPhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.txnPhotoRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(VN.remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      await ref
          .read(orderPaymentTransactionsProvider(widget.orderRef).notifier)
          .detachPhoto(widget.txn.id);
      if (mounted) {
        showTopSnackBar(context, VN.txnPhotoRemoved);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, '${VN.txnPhotoSaveFailed}: $e');
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  /// Renders the per-transaction photo section: thumbnail (tap to enlarge),
  /// Replace and Remove buttons when a photo is attached; Attach button when
  /// none. Reuses [OrderPhotoThumbnail] / [OrderPhotoViewer] (FR3 / AC2).
  Widget _buildTxnPhotoSection(
    WidgetRef ref,
    ThemeData theme,
    String baseUrl,
  ) {
    final photoAsync =
        ref.watch(transactionPhotoProvider((widget.orderRef, widget.txn.id)));
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
              // No photo attached — show the attach button.
              return Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: VN.txnPhotoAttach,
                  child: TextButton.icon(
                    onPressed: _photoBusy ? null : _pickTxnPhoto,
                    icon:
                        const Icon(Icons.photo_camera_outlined, size: 20),
                    label: const Text(VN.txnPhotoAttach),
                  ),
                ),
              );
            }
            final url = '$baseUrl/api/photos/${photo.photoHash}.jpg';
            // Synthesize an [OrderPhoto] so the shared [OrderPhotoViewer]
            // (which only reads photoHash + tags) can display the single
            // transaction photo full-screen (FR4 reuse).
            final viewerPhoto = OrderPhoto(
              id: int.tryParse(photo.id) ?? 0,
              orderId: 0,
              photoHash: photo.photoHash!,
              tags: 'chuyen-khoan',
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OrderPhotoThumbnail(
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: VN.txnPhotoReplace,
                        child: TextButton.icon(
                          onPressed:
                              _photoBusy ? null : _pickTxnPhoto,
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          label: const Text(VN.txnPhotoReplace),
                        ),
                      ),
                      Tooltip(
                        message: VN.txnPhotoRemove,
                        child: TextButton.icon(
                          onPressed:
                              _photoBusy ? null : _removeTxnPhoto,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text(VN.txnPhotoRemove),
                        ),
                      ),
                    ],
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseUrl = ref.watch(apiBaseUrlProvider);

    const types = [
      ('deposit', VN.txnTypeDeposit),
      ('payment', VN.txnTypePayment),
      ('full_payment', VN.txnTypeFullPayment),
      ('refund', VN.txnTypeRefund),
    ];
    const methods = [('cash', VN.methodCash), ('transfer', VN.methodTransfer)];

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
            Text(VN.editPayment, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Text(VN.txnType, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: types
                  .map(
                    (t) => ChoiceChip(
                      label: Text(t.$2),
                      selected: _type == t.$1,
                      onSelected: (_) => setState(() => _type = t.$1),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text(VN.paymentMethod, style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: methods
                  .map(
                    (m) => ChoiceChip(
                      label: Text(m.$2),
                      selected: _method == m.$1,
                      onSelected: (_) => setState(() {
                    _method = m.$1;
                    if (m.$1 != 'transfer') _paymentSource = null;
                  }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: VN.paymentAmountLabel,
                border: OutlineInputBorder(),
                suffixText: ',000đ',
                helperText: VN.paymentThousandsHint,
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return VN.fieldRequired;
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return VN.invalidPrice;
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: VN.paymentNotes,
                border: OutlineInputBorder(),
              ),
            ),
            if (_method == 'transfer') ...[
              const SizedBox(height: 12),
              TargetAccountDropdown(
                value: _paymentSource,
                onChanged: (value) =>
                    setState(() => _paymentSource = value),
              ),
            ],
            const SizedBox(height: 12),
            _buildTxnPhotoSection(ref, theme, baseUrl),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(VN.editPayment),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}