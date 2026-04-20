import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/models/order.dart';
import '../../../providers/order_providers.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

/// Unified OrderCard widget for use across order list, kanban, and dashboard.
///
/// Displays all FR-5 card content items:
/// - Main product names with prices (non-extra items only)
/// - Delivery type icon
/// - orderRef prominently
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
    this.compact = false,
    this.onTap,
  });

  final Order order;
  final bool compact;
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

  // ── Urgency helpers ───────────────────────────────────────────────────

  /// Returns the urgency border color: red for overdue, amber for same-day, null otherwise.
  Color? _urgencyBorderColor() {
    if (order.dueDate == null || order.dueDate!.isEmpty) return null;
    try {
      final due = DateTime.parse(order.dueDate!);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueDateOnly = DateTime(due.year, due.month, due.day);
      if (dueDateOnly.isBefore(today)) {
        return Colors.red;
      } else if (dueDateOnly.isAtSameMomentAs(today)) {
        return Colors.amber;
      }
    } catch (_) {}
    return null;
  }

  /// Returns true if the order is due within the next 2 hours.
  bool _isDueWithin2Hours() {
    if (order.dueDate == null || order.dueDate!.isEmpty) return false;
    try {
      final now = DateTime.now();
      DateTime due;
      if (order.dueTime != null && order.dueTime!.isNotEmpty) {
        due = DateTime.parse('${order.dueDate!} ${order.dueTime!}');
      } else {
        due = DateTime.parse(order.dueDate!);
      }
      return due.isAfter(now) && due.difference(now).inMinutes <= 120;
    } catch (_) {}
    return false;
  }

  // ── Delivery icon helpers ─────────────────────────────────────────────

  IconData _deliveryIcon() {
    switch (order.deliveryType) {
      case 'bus':
        return Icons.directions_bus;
      case 'door':
        return Icons.local_shipping;
      case 'pickup':
      default:
        return Icons.storefront;
    }
  }

  Color _deliveryIconColor(Color defaultColor) {
    switch (order.deliveryType) {
      case 'bus':
        return Colors.orange;
      case 'door':
        return Colors.deepOrange;
      default:
        return defaultColor;
    }
  }

  bool get _isDelivery =>
      order.deliveryType == 'bus' || order.deliveryType == 'door';

  // ── Product names ───────────────────────────────────────────────────────

  /// Returns formatted product names string: "Name 150.000đ, Name2 80.000đ"
  /// Only includes items where isExtra == false.
  String _productNamesLine() {
    final nonExtra = order.items.where((i) => !i.isExtra).toList();
    if (nonExtra.isEmpty) return '';

    final parts = <String>[];
    for (final item in nonExtra) {
      parts.add('${item.productName} ${formatVND(item.unitPrice)}');
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
    final statusColor = BakeryTheme.statusColors[order.status] ?? Colors.grey;
    final statusLabel = statusMap[order.status] ?? order.status;
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

    final urgencyColor = _urgencyBorderColor();
    final dueSoon = _isDueWithin2Hours();

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
              // ── Top row: delivery icon, order ref, photo badge, status chip ──
              Row(
                children: [
                  Icon(
                    _deliveryIcon(),
                    size: _isDelivery ? 20 : 18,
                    color: _deliveryIconColor(theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.orderRef,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withAlpha(120)),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              // ── Print status sub-label ──
              if (!compact &&
                  (order.status == 'confirmed' ||
                      order.status == 'in_progress')) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Spacer(),
                    if (order.workTicketPrintedAt != null) ...[
                      Icon(
                        Icons.check_circle_outline,
                        size: 12,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        VN.printStatusPrinted,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.green.shade600,
                          fontSize: 10,
                        ),
                      ),
                    ] else ...[
                      Icon(
                        Icons.print_outlined,
                        size: 12,
                        color: Colors.orange.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        VN.printStatusUnprinted,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.orange.shade600,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              if (!compact) const SizedBox(height: 4),

              // ── Product names (non-compact only) ──
              if (!compact) ...[
                Text(
                  _productNamesLine(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
              ],

              // ── Customer name + source badge ──
              Row(
                children: [
                  Text(
                    order.customerName,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (order.source.isNotEmpty) ...[
                    const SizedBox(width: 6),
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

              // ── Notes preview (non-compact only) ──
              if (!compact && order.notes.isNotEmpty) ...[
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
                          ? Colors.red
                          : (urgencyColor ?? theme.colorScheme.outline),
                    ),
                    const SizedBox(width: 4),
                    if (dueSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: Colors.red.withAlpha(80)),
                        ),
                        child: Text(
                          _formatDue(order.dueDate, order.dueTime),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.red,
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
