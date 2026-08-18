import 'package:flutter/material.dart';

import '../../../../data/models/order.dart';
import '../../../../data/models/order_photo.dart';
import '../../../../data/models/payment_transaction.dart';
import 'order_payment_history.dart';
import 'order_payment_row.dart';
import 'order_photo_thumbnail.dart';
import '../order_photo_section.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Transactions tab content: payment summary at the top (total, paid,
/// remaining), an "add transaction" button that opens
/// [OrderRecordPaymentSheet], then the existing [OrderPaymentHistory] list,
/// followed by a photo section showing `chuyen-khoan` tagged photos.
///
/// The summary reuses the [OrderPaymentRow] pattern from
/// [OrderPaymentSummary] (NFR1: no extra network fetch on tab switch — the
/// `order`, `amountPaid`, `remaining`, and `transferPhotos` values are
/// forwarded from the parent [OrderDetailScreen] which already watches
/// `orderPhotosProvider`).
class OrderDetailTransactionsTab extends StatelessWidget {
  const OrderDetailTransactionsTab({
    super.key,
    required this.order,
    required this.amountPaid,
    required this.remaining,
    required this.txns,
    required this.onAddPayment,
    required this.onTransactionTap,
    required this.transferPhotos,
    required this.baseUrl,
  });

  final Order order;
  final double amountPaid;
  final double remaining;
  final List<PaymentTransaction> txns;
  final VoidCallback onAddPayment;
  final void Function(PaymentTransaction txn) onTransactionTap;

  /// Order photos tagged `chuyen-khoan` to display as transfer proof below
  /// the payment history. Filtered and forwarded by the parent
  /// [OrderDetailScreen] from `orderPhotosProvider` (NFR1).
  final List<OrderPhoto> transferPhotos;

  /// Base API URL used to build photo thumbnail URLs.
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _TransactionsSummary(
          order: order,
          amountPaid: amountPaid,
          remaining: remaining,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAddPayment,
          icon: const Icon(Icons.add, size: 18),
          label: const Text(VN.orderDetailAddTransaction),
        ),
        const SizedBox(height: 16),
        OrderPaymentHistory(txns: txns, onTransactionTap: onTransactionTap),
        const SizedBox(height: 16),
        _TransferPhotoSection(
          photos: transferPhotos,
          baseUrl: baseUrl,
        ),
      ],
    );
  }
}

/// Compact payment summary card for the transactions tab. Renders the three
/// key amounts (total, paid, remaining) using the shared [OrderPaymentRow]
/// widget so the layout matches [OrderPaymentSummary].
class _TransactionsSummary extends StatelessWidget {
  const _TransactionsSummary({
    required this.order,
    required this.amountPaid,
    required this.remaining,
  });

  final Order order;
  final double amountPaid;
  final double remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remainingColor =
        remaining > 0 ? theme.colorScheme.error : Colors.green;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          OrderPaymentRow(
            label: VN.total,
            value: formatVND(order.totalPrice),
            valueStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          OrderPaymentRow(
            label: VN.amountPaidLabel,
            value: formatVND(amountPaid),
            valueStyle: theme.textTheme.bodyMedium?.copyWith(
              color: amountPaid > 0 ? Colors.green : null,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          OrderPaymentRow(
            label: VN.remainingLabel,
            value: formatVND(remaining),
            valueStyle: theme.textTheme.bodyMedium?.copyWith(
              color: remainingColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Photo section shown below the payment history in the Transactions tab.
/// Displays order photos tagged `chuyen-khoan` as a horizontal thumbnail
/// strip with tag chips, reusing the [OrderPhotoThumbnail] widget and
/// [OrderPhotoViewer] from [order_photo_section.dart] (FR1 / AC1).
///
/// NFR1: the [photos] list is forwarded by the parent — this widget performs
/// no network fetch of its own.
class _TransferPhotoSection extends StatelessWidget {
  const _TransferPhotoSection({required this.photos, required this.baseUrl});

  final List<OrderPhoto> photos;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          VN.transferPhotosSection,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        if (photos.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              VN.noTransferPhotos,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          SizedBox(
            height: 134,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 4),
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (ctx, index) {
                final photo = photos[index];
                final url = '$baseUrl/api/photos/${photo.photoHash}.jpg';
                return OrderPhotoThumbnail(
                  url: url,
                  tags: photo.tags,
                  onTap: () => Navigator.of(ctx).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OrderPhotoViewer(
                        photos: photos,
                        initialIndex: index,
                        baseUrl: baseUrl,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}