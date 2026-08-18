import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart'
    show ImagePicker, ImageSource, XFile;

import '../../../../data/api/api_client.dart' show apiBaseUrlProvider;
import '../../../../data/models/order_photo.dart';
import '../../../../providers/order_providers.dart';
import '../../../pos/widgets/pos_checkout_dialogs.dart';
import 'order_photo_thumbnail.dart';
import '../order_photo_section.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// Shared per-transaction photo section used by both the edit-payment and
/// transaction-detail sheets (DG-410 CQ-1).
///
/// Renders the attach / replace / remove controls around the
/// [transactionPhotoProvider] state and centralizes the
/// `_pickTxnPhoto` / `_removeTxnPhoto` / `_photoBusy` logic that was
/// previously duplicated across the two sheets. The two sheets differ only
/// in which actions are exposed:
/// - Edit sheet: shows attach + replace + remove.
/// - Detail sheet: shows attach/replace, plus an inline empty-state row
///   (`showEmptyState`) and never a remove button.
class TxnPhotoSection extends ConsumerStatefulWidget {
  const TxnPhotoSection({
    super.key,
    required this.orderRef,
    required this.txnId,
    this.showRemove = true,
    this.showEmptyState = false,
  });

  final String orderRef;
  final String txnId;

  /// Whether to render the "Remove" button when a photo is attached.
  /// The edit sheet exposes remove; the detail sheet does not.
  final bool showRemove;

  /// When true, the no-photo state renders an inline row with an
  /// [OrdersLabels.txnPhotoEmpty] label next to the attach button (detail sheet). When
  /// false, the empty state is a single left-aligned attach button
  /// (edit sheet).
  final bool showEmptyState;

  @override
  ConsumerState<TxnPhotoSection> createState() => _TxnPhotoSectionState();
}

class _TxnPhotoSectionState extends ConsumerState<TxnPhotoSection> {
  bool _photoBusy = false;

  String get _orderRef => widget.orderRef;
  String get _txnId => widget.txnId;

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
          .read(orderPaymentTransactionsProvider(_orderRef).notifier)
          .attachPhoto(_txnId, image);
      if (mounted) {
        showTopSnackBar(context, OrdersLabels.txnPhotoSaved);
      }
    } catch (e, st) {
      // CQ-3: log the exception detail for diagnostics but never surface
      // raw exception text in the user-facing snackbar — show the stable
      // VN label only.
      debugPrint('attachPhoto failed: $e\n$st');
      if (mounted) {
        showTopSnackBar(context, OrdersLabels.txnPhotoSaveFailed);
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
        title: const Text(OrdersLabels.txnPhotoRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(SharedLabels.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(SharedLabels.remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      await ref
          .read(orderPaymentTransactionsProvider(_orderRef).notifier)
          .detachPhoto(_txnId);
      if (mounted) {
        showTopSnackBar(context, OrdersLabels.txnPhotoRemoved);
      }
    } catch (e, st) {
      debugPrint('detachPhoto failed: $e\n$st');
      if (mounted) {
        showTopSnackBar(context, OrdersLabels.txnPhotoSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final photoAsync =
        ref.watch(transactionPhotoProvider((_orderRef, _txnId)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(OrdersLabels.txnPhotoSection, style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        photoAsync.when(
          loading: () => const SizedBox(
            height: 90,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, st) {
            // CQ-3: surface the stable label, not raw exception text.
            debugPrint('transactionPhotoProvider error: $e\n$st');
            return Text(
              OrdersLabels.txnPhotoSaveFailed,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            );
          },
          data: (photo) {
            if (photo == null || photo.photoHash == null) {
              // No photo attached.
              if (widget.showEmptyState) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        OrdersLabels.txnPhotoEmpty,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: OrdersLabels.txnPhotoAttach,
                      child: TextButton.icon(
                        onPressed: _photoBusy ? null : _pickTxnPhoto,
                        icon:
                            const Icon(Icons.photo_camera_outlined, size: 20),
                        label: const Text(OrdersLabels.txnPhotoAttach),
                      ),
                    ),
                  ],
                );
              }
              return Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: OrdersLabels.txnPhotoAttach,
                  child: TextButton.icon(
                    onPressed: _photoBusy ? null : _pickTxnPhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 20),
                    label: const Text(OrdersLabels.txnPhotoAttach),
                  ),
                ),
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
                  message: OrdersLabels.txnPhotoTapToEnlarge,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: OrdersLabels.txnPhotoReplace,
                        child: TextButton.icon(
                          onPressed: _photoBusy ? null : _pickTxnPhoto,
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          label: const Text(OrdersLabels.txnPhotoReplace),
                        ),
                      ),
                      if (widget.showRemove)
                        Tooltip(
                          message: OrdersLabels.txnPhotoRemove,
                          child: TextButton.icon(
                            onPressed: _photoBusy ? null : _removeTxnPhoto,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text(OrdersLabels.txnPhotoRemove),
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
}