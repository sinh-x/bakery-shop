import 'package:flutter/material.dart';

import '../../../shared/labels/orders.dart';

/// Read-only tappable Google Maps link row (AC2/AC4).
/// Extracted from [OrderDeliverySection] to keep the parent widget under the
/// 400-line Flutter coding-standards limit.
///
/// DG-329 Phase 7 / FR9: the editable `GpsFieldsSection` (manual Lat/Long
/// TextFormFields) was removed from the wizard. Stored coordinates are now
/// managed exclusively via the Google Maps modal on the order detail screen.
/// This `MapLinkRow` is retained for read-only display of the stored URL.
class MapLinkRow extends StatelessWidget {
  const MapLinkRow({
    super.key,
    required this.url,
    required this.onTap,
  });

  final String url;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.map_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              '${OrdersLabels.googleMapsUrlLabel}:',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        OrdersLabels.openMap,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}