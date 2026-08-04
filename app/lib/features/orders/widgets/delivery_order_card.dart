import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/api_client.dart';
import '../../../data/models/order.dart';
import '../../../providers/order_providers.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/utils/launch_external_url.dart';
import '../../../shared/utils/delivery_helpers.dart';
import '../../../shared/utils/order_helpers.dart';
import 'delivery_claim_actions.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class DeliveryOrderCard extends ConsumerWidget {
  const DeliveryOrderCard({super.key, required this.order, this.onTap});

  final Order order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusColor = BakeryTheme.statusColors[order.status] ?? Colors.grey;
    final statusLabel = statusMap[order.status] ?? order.status;
    final photosAsync = ref.watch(orderPhotosProvider(order.orderRef));
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final urgencyColor = urgencyBorderColor(order.dueDate);
    final dueSoon = isDueWithin2Hours(order.dueDate, order.dueTime);
    final borderColor = urgencyColor ?? Colors.transparent;

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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: borderColor, width: 4),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    deliveryIcon(order.deliveryType),
                    size: 20,
                    color: deliveryIconColor(
                      order.deliveryType,
                      theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      visualOrderCode(
                        orderRef: order.orderRef,
                        publicOrderCode: order.publicOrderCode,
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (cakePhotoUrl != null) ...[
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
                          color:
                              theme.colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 40,
                          height: 40,
                          color:
                              theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 20,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: statusColor.withAlpha(120),
                      ),
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
              const SizedBox(height: 4),
              Text(order.customerName, style: theme.textTheme.bodyMedium),
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
              if (_hasGpsOrMap(order)) ...[
                const SizedBox(height: 4),
                _buildGpsMapRow(context, theme),
              ],
              // DG-306 Phase 1 / FR1: auto-derive the slot from `dueTime`
              // (the stored `deliveryTimeSlot` DB column is ignored).
              if (deriveTimeSlot(order.dueTime) case final slot?) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${OrdersLabels.deliveryTimeSlotLabel} $slot',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              if (order.dueDate != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: dueSoon
                          ? Colors.orange
                          : (urgencyColor ??
                              theme.colorScheme.outline),
                    ),
                    const SizedBox(width: 4),
                    if (dueSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.orange.withAlpha(80),
                          ),
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
                          color: urgencyColor ??
                              theme.colorScheme.outline,
                          fontWeight: urgencyColor != null
                              ? FontWeight.bold
                              : null,
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
                  ],
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  formatVND(order.totalPrice),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              DeliveryClaimActions(order: order),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDue(String? dueDate, String? dueTime) {
    if (dueDate == null) return '';
    return dueTime != null ? '$dueDate $dueTime' : dueDate;
  }

  /// Whether the order exposes any GPS/map data worth rendering (AC3).
  bool _hasGpsOrMap(Order order) {
    final hasCoords = order.latitude != null && order.longitude != null;
    final hasMapUrl =
        order.googleMapsUrl != null && order.googleMapsUrl!.trim().isNotEmpty;
    return hasCoords || hasMapUrl;
  }

  /// GPS coordinates + tappable map link row (AC3). Reuses the
  /// `url_launcher` + `canLaunchUrl` + snackbar-on-failure pattern from
  /// `order_detail_screen.dart::_launchMapUrl`.
  Widget _buildGpsMapRow(BuildContext context, ThemeData theme) {
    final coords = (order.latitude != null && order.longitude != null)
        ? '${order.latitude!.toStringAsFixed(5)}, ${order.longitude!.toStringAsFixed(5)}'
        : null;
    final mapUrl = order.googleMapsUrl;
    final hasMapUrl = mapUrl != null && mapUrl.trim().isNotEmpty;

    return Row(
      children: [
        Icon(
          Icons.location_on_outlined,
          size: 14,
          color: theme.colorScheme.tertiary,
        ),
        const SizedBox(width: 4),
        if (coords != null)
          Expanded(
            child: Text(
              coords,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          )
        else
          Expanded(
            child: Text(
              OrdersLabels.googleMapsUrlLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        if (hasMapUrl) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: () => launchExternalUrl(context, mapUrl),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                OrdersLabels.openMap,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
