import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/models/order.dart';
import '../../../providers/order_providers.dart';
import '../../../shared/utils/order_helpers.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

/// Unified OrderCard widget for use across order list, kanban, and dashboard.
///
/// Displays all FR-5 card content items:
/// - Main product names with prices (non-extra items only)
/// - Delivery type icon
/// - customer name + source badge
/// - due date/time with urgency coloring
/// - total price
/// - status chip
/// - photo thumbnail (first cake photo)
/// - print status indicator
/// - notes preview
///
/// Also includes:
/// - Payment badge (FR-2): Đã TT / Cọc / Chưa TT
/// - Urgency indicators (FR-3): overdue red, due-soon amber, today subtle
class OrderCard extends ConsumerWidget {
  const OrderCard({
    super.key,
    required this.order,
    this.onTap,
  });

  final Order order;
  final VoidCallback? onTap;

  // ── Payment badge helpers ───────────────────────────────────────────────

  /// Returns payment badge color and label.
  (Color, String) _paymentBadge() {
    if (order.isPaid) {
      return (Colors.green, 'Đã TT');
    } else if (order.amountPaid > 0) {
      return (Colors.orange, 'Cọc');
    } else {
      return (Colors.red, 'Chưa TT');
    }
  }

  // ── Urgency/delivery helpers delegated to shared order_helpers.dart ──

  // ── Product names ───────────────────────────────────────────────────────

  /// Returns formatted product names string: "Name 150.000đ, Name2 80.000đ"
  /// Only includes items where isExtra == false.
  /// Truncated to max 40 chars per name segment with ellipsis.
  String _productNamesLine() {
    final nonExtra = order.items.where((i) => !i.isExtra).toList();
    if (nonExtra.isEmpty) return '';

    final parts = <String>[];
    for (final item in nonExtra) {
      final name = item.productName;
      final price = formatVND(item.unitPrice);
      // Truncate single product name segment to 40 chars
      final maxLen = 40;
      final full = '$name $price';
      if (full.length <= maxLen) {
        parts.add(full);
      } else {
        final allowedLen = max(0, maxLen - price.length - 4);
        final truncated = name.length > allowedLen
            ? '${name.substring(0, allowedLen)}... $price'
            : full;
        parts.add(truncated);
      }
    }
    return parts.join(', ');
  }

  // ── Due date formatting ─────────────────────────────────────────────────

  String _formatDue(String? dueDate, String? dueTime) {
    if (dueDate == null) return '';
    // YYYY-MM-DD → DD/MM for display
    final parts = dueDate.split('-');
    final formatted =
        parts.length == 3 ? '${parts[2]}/${parts[1]}' : dueDate;
    return dueTime != null && dueTime.isNotEmpty
        ? '$formatted $dueTime'
        : formatted;
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final photosAsync = ref.watch(orderPhotosProvider(order.orderRef));
    final baseUrl = ref.watch(apiBaseUrlProvider);

    final photoCount = photosAsync.maybeWhen(
      data: (photos) => photos.length,
      orElse: () => 0,
    );

    // Find the first cake photo (workItemId != null) for thumbnail
    final cakePhoto = photosAsync.maybeWhen(
      data: (photos) {
        try {
          return photos.firstWhere((p) => p.workItemId != null);
        } catch (_) {
          return null;
        }
      },
      orElse: () => null,
    );
    final cakePhotoUrl = cakePhoto != null
        ? '$baseUrl/api/photos/${cakePhoto.photoHash}.jpg'
        : null;

    final urgencyColor = urgencyBorderColor(order.dueDate);
    final dueSoon = isDueWithin2Hours(order.dueDate, order.dueTime);

    // Build left border decoration
    final borderSides = <BorderSide>[];
    if (urgencyColor != null) {
      borderSides.add(BorderSide(color: urgencyColor, width: 4));
    }
    if (borderSides.isEmpty) {
      borderSides.add(const BorderSide(color: Colors.transparent, width: 4));
    }

    final paymentColor = _paymentBadge().$1;
    final paymentLabel = _paymentBadge().$2;
    final isTerminal =
        ['completed', 'cancelled', 'delivered'].contains(order.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: borderSides.first),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Customer name + delivery icon (own line, above everything) ──
              Row(
                children: [
                  Icon(
                    deliveryIcon(order.deliveryType),
                    size: isDeliveryType(order.deliveryType) ? 20 : 18,
                    color: deliveryIconColor(order.deliveryType, theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.customerName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              // ── Photo badge + thumbnail (below name row) ──
              Row(
                children: [
                  const Spacer(),
                  if (photoCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.photo_outlined,
                            size: 11,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '$photoCount ảnh',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  // Cake photo thumbnail
                  if (cakePhotoUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: cakePhotoUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 40,
                          height: 40,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 40,
                          height: 40,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 20,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                  if (cakePhotoUrl != null) const SizedBox(width: 6),
                ],
              ),

              // ── Print status sub-label ──
              // Terminal statuses: print indicator is irrelevant
              if (!isTerminal) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Spacer(),
                    if (order.workTicketPrintedAt != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Text(
                          VN.printStatusPrintedShort,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.green.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ] else if (order.status == 'confirmed' ||
                        order.status == 'in_progress') ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          VN.printStatusUnprintedShort,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.orange.shade800,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              const SizedBox(height: 4),

              // ── Product names ──
              Text(
                _productNamesLine(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),

              // ── Customer name + source badge ──
              Row(
                children: [
                  if (order.source.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        order.source,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // ── Notes preview ──
              if (order.notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  order.notes,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],

              // ── Due date row + price + payment badge ──
              if (order.dueDate != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      dueSoon ? Icons.warning_amber_rounded : Icons.schedule,
                      size: 14,
                      color: dueSoon
                          ? Colors.orange
                          : (urgencyColor ?? theme.colorScheme.outline),
                    ),
                    const SizedBox(width: 4),
                    if (dueSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: Colors.orange.withAlpha(80)),
                        ),
                        child: Text(
                          _formatDue(order.dueDate, order.dueTime),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      Text(
                        _formatDue(order.dueDate, order.dueTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              urgencyColor ?? theme.colorScheme.outline,
                          fontWeight:
                              urgencyColor != null ? FontWeight.bold : null,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Text(
                      formatVND(order.totalPrice),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    // Payment badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: paymentColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: paymentColor.withAlpha(100)),
                      ),
                      child: Text(
                        paymentLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: paymentColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      formatVND(order.totalPrice),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    // Payment badge (no due date)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: paymentColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: paymentColor.withAlpha(100)),
                      ),
                      child: Text(
                        paymentLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: paymentColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
